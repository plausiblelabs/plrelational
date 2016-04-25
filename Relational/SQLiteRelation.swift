
import sqlite3

class SQLiteRelation: Relation {
    let db: SQLiteDatabase
    
    let tableName: String
    
    var tableNameForQuery: String {
        return db.escapeIdentifier(tableName)
    }
    
    let query: String
    let queryParameters: [RelationValue]
    
    init(db: SQLiteDatabase, tableName: String, query: String, queryParameters: [RelationValue]) {
        self.db = db
        self.tableName = tableName
        self.query = query
        self.queryParameters = queryParameters
    }
    
    var scheme: Scheme {
        let columns = try! executeQuery("pragma table_info(\(tableNameForQuery))")
        return Scheme(attributes: Set(columns.map({ Attribute($0["name"].get()!) })))
    }
    
    func rows() -> AnyGenerator<Row> {
        return try! executeQuery("SELECT * FROM (\(query))", queryParameters)
    }
    
    func contains(row: Row) -> Bool {
        fatalError("unimplemented")
    }
}

extension SQLiteRelation {
    private func executeQuery(sql: String, _ parameters: [RelationValue] = []) throws -> AnyGenerator<Row> {
        let stmt = try SQLiteStatement(sqliteCall: { try db.errwrap(sqlite3_prepare_v2(db.db, sql, -1, &$0, nil)) })
        for (index, param) in parameters.enumerate() {
            try self.bindValue(stmt.stmt, Int32(index + 1), param)
        }
        
        return AnyGenerator(body: {
            let result = sqlite3_step(stmt.stmt)
            if result == SQLITE_DONE { return nil }
            if result != SQLITE_ROW {
                fatalError("Got a result from sqlite3_step that I don't know how to handle: \(result)")
            }
            
            var row = Row(values: [:])
            
            let columnCount = sqlite3_column_count(stmt.stmt)
            for i in 0..<columnCount {
                let name = String.fromCString(sqlite3_column_name(stmt.stmt, i))
                let value = self.columnToValue(stmt.stmt, i)
                row[Attribute(name!)] = value
            }
            
            return row
        })
    }
    
    private func columnToValue(stmt: sqlite3_stmt, _ index: Int32) -> RelationValue {
        let type = sqlite3_column_type(stmt, index)
        switch type {
        case SQLITE_NULL: return .NULL
        case SQLITE_INTEGER: return .Integer(sqlite3_column_int64(stmt, index))
        case SQLITE_FLOAT: return .Real(sqlite3_column_double(stmt, index))
        case SQLITE_TEXT: return .Text(String.fromCString(UnsafePointer(sqlite3_column_text(stmt, index)))!)
        case SQLITE_BLOB:
            let ptr = UnsafePointer<UInt8>(sqlite3_column_blob(stmt, index))
            let length = sqlite3_column_bytes(stmt, index)
            let buffer = UnsafeBufferPointer<UInt8>(start: ptr, count: Int(length))
            return .Blob(Array(buffer))
        default:
            fatalError("Got unknown column type \(type) from SQLite")
        }
    }
    
    private func bindValue(stmt: sqlite3_stmt, _ index: Int32, _ value: RelationValue) throws {
        switch value {
        case .NULL: try db.errwrap(sqlite3_bind_null(stmt, index))
        case .Integer(let x): try db.errwrap(sqlite3_bind_int64(stmt, index, x))
        case .Real(let x): try db.errwrap(sqlite3_bind_double(stmt, index, x))
        case .Text(let x): try db.errwrap(sqlite3_bind_text(stmt, index, x, -1, SQLITE_TRANSIENT))
        case .Blob(let x): try db.errwrap(sqlite3_bind_blob64(stmt, index, x, UInt64(x.count), SQLITE_TRANSIENT))
        }
    }
}

extension SQLiteRelation {
    private func valueProviderToSQL(provider: ValueProvider) -> (String, RelationValue?)? {
        switch provider {
        case let provider as Attribute:
            return (db.escapeIdentifier(provider.name), nil)
        case let provider as String:
            return ("?", RelationValue.Text(provider))
        case let provider as RelationValue:
            return ("?", provider)
        default:
            return nil
        }
    }
    
    private func comparatorToSQL(op: Comparator) -> String? {
        switch op {
        case is EqualityComparator:
            return " = "
        default:
            return nil
        }
    }
    
    private func termsToSQL(terms: [ComparisonTerm]) -> (String, [RelationValue])? {
        var sqlPieces: [String] = []
        var sqlParameters: [RelationValue] = []
        
        for term in terms {
            guard
                let (lhs, lhsParam) = valueProviderToSQL(term.lhs),
                let op = comparatorToSQL(term.op),
                let (rhs, rhsParam) = valueProviderToSQL(term.rhs)
                else { return nil }
            
            sqlPieces.append(lhs + op + rhs)
            if let l = lhsParam {
                sqlParameters.append(l)
            }
            if let r = rhsParam {
                sqlParameters.append(r)
            }
        }
        
        let parenthesizedPieces = sqlPieces.map({ "(" + $0 + ")" })
        
        return (parenthesizedPieces.joinWithSeparator(" AND "), sqlParameters)
    }
    
    func select(terms: [ComparisonTerm]) -> Relation {
        if let (sql, parameters) = termsToSQL(terms) {
            return SQLiteRelation(db: db, tableName: self.tableName, query: "SELECT * FROM (\(self.query)) WHERE \(sql)", queryParameters: self.queryParameters + parameters)
        } else {
            return SelectRelation(relation: self, terms: terms)
        }
    }
}

class SQLiteTableRelation: SQLiteRelation {
    init(db: SQLiteDatabase, tableName: String) {
        super.init(db: db, tableName: tableName, query: db.escapeIdentifier(tableName), queryParameters: [])
    }
    
    func add(row: Row) throws -> Int64 {
        let orderedAttributes = Array(row.values)
        let attributesSQL = orderedAttributes.map({ db.escapeIdentifier($0.0.name) }).joinWithSeparator(", ")
        let parameters = orderedAttributes.map({ $0.1 })
        let valuesSQL = Array(count: orderedAttributes.count, repeatedValue: "?").joinWithSeparator(", ")
        let sql = "INSERT INTO \(tableNameForQuery) (\(attributesSQL)) VALUES (\(valuesSQL))"
        
        let result = try executeQuery(sql, parameters)
        precondition(Array(result) == [], "Shouldn't get results back from an insert query")
        
        return sqlite3_last_insert_rowid(db.db)
    }
    
    func delete(searchTerms: [ComparisonTerm]) throws {
        if let (whereSQL, whereParameters) = termsToSQL(searchTerms) {
            let sql = "DELETE FROM \(tableNameForQuery) WHERE \(whereSQL)"
            let result = try executeQuery(sql, whereParameters)
            precondition(Array(result) == [], "Shouldn't get results back from a delete query")
        } else {
            fatalError("Don't know how to transform these search terms into SQL, and we haven't implemented non-SQL deletes: \(searchTerms)")
        }
    }
    
    func update(searchTerms: [ComparisonTerm], newValues: Row) throws {
        if let (whereSQL, whereParameters) = termsToSQL(searchTerms) {
            let orderedAttributes = Array(newValues.values)
            let setParts = orderedAttributes.map({ db.escapeIdentifier($0.0.name) + " = ?" })
            let setSQL = setParts.joinWithSeparator(", ")
            let setParameters = orderedAttributes.map({ $0.1 })
            
            let sql = "UPDATE \(tableNameForQuery) SET \(setSQL) WHERE \(whereSQL)"
            let result = try executeQuery(sql, setParameters + whereParameters)
            precondition(Array(result) == [], "Shouldn't get results back from an update query")
        } else {
            fatalError("Don't know how to transform these search terms into SQL, and we haven't implemented non-SQL updates: \(searchTerms)")
        }
    }
}

