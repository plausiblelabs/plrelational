
import sqlite3

class SQLiteRelation: Relation {
    let db: SQLiteDatabase
    
    let tableName: String
    
    var tableNameForQuery: String {
        return db.escapeIdentifier(tableName)
    }
    
    let query: String
    let queryParameters: [String]
    
    init(db: SQLiteDatabase, tableName: String, query: String, queryParameters: [String]) {
        self.db = db
        self.tableName = tableName
        self.query = query
        self.queryParameters = queryParameters
    }
    
    var scheme: Scheme {
        let columns = try! query("pragma table_info(\(tableNameForQuery))")
        return Scheme(attributes: Set(columns.map({ Attribute($0["name"]) })))
    }
    
    func rows() -> AnyGenerator<Row> {
        return try! query("SELECT * FROM (\(query))", queryParameters)
    }
    
    func contains(row: Row) -> Bool {
        fatalError("unimplemented")
    }
}

class SQLiteTableRelation: SQLiteRelation {
    init(db: SQLiteDatabase, tableName: String) {
        super.init(db: db, tableName: tableName, query: db.escapeIdentifier(tableName), queryParameters: [])
    }
    
    func add(row: Row) throws {
        let orderedAttributes = Array(row.values.keys)
        let attributesSQL = orderedAttributes.map({ db.escapeIdentifier($0.name) }).joinWithSeparator(", ")
        let valuesSQL = Array(count: orderedAttributes.count, repeatedValue: "?").joinWithSeparator(", ")
        let sql = "INSERT INTO \(tableNameForQuery) (\(attributesSQL)) VALUES (\(valuesSQL))"
        
        let stmt = try SQLiteStatement(sqliteCall: { try db.errwrap(sqlite3_prepare_v2(db.db, sql, -1, &$0, nil)) })
        
        for (index, attribute) in orderedAttributes.enumerate() {
            try db.errwrap(sqlite3_bind_text(stmt.stmt, Int32(index + 1), row[attribute], -1, SQLITE_TRANSIENT))
        }
        
        let result = try db.errwrap(sqlite3_step(stmt.stmt))
        if result != SQLITE_DONE {
            throw SQLiteDatabase.Error(code: result, message: "Unexpected non-error result stepping INSERT INTO statement: \(result)")
        }
    }
    
    func delete(row: Row) {
        fatalError("unimplemented")
    }
    
    func change(rowToFind: Row, to: Row) {
        fatalError("unimplemented")
    }
}

extension SQLiteRelation {
    private func query(sql: String, _ parameters: [String] = []) throws -> AnyGenerator<Row> {
        let stmt = try SQLiteStatement(sqliteCall: { try db.errwrap(sqlite3_prepare_v2(db.db, sql, -1, &$0, nil)) })
        for (index, param) in parameters.enumerate() {
            try db.errwrap(sqlite3_bind_text(stmt.stmt, Int32(index + 1), param, -1, SQLITE_TRANSIENT))
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
                let value = String.fromCString(UnsafePointer(sqlite3_column_text(stmt.stmt, i)))
                if let value = value {
                    row[Attribute(name!)] = value
                }
            }
            
            return row
        })
    }
}

extension SQLiteRelation {
    private func valueProviderToSQL(provider: ValueProvider) -> (String, String?)? {
        switch provider {
        case let provider as Attribute:
            return (db.escapeIdentifier(provider.name), nil)
        case let provider as String:
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
    
    private func termsToSQL(terms: [ComparisonTerm]) -> (String, [String])? {
        var sqlPieces: [String] = []
        var sqlParameters: [String] = []
        
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
