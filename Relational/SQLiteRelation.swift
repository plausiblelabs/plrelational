
import sqlite3

public class SQLiteRelation: Relation {
    let db: SQLiteDatabase
    
    let tableName: String
    public let scheme: Scheme
    
    var tableNameForQuery: String {
        return db.escapeIdentifier(tableName)
    }
    
    let query: String
    let queryParameters: [RelationValue]
    
    init(db: SQLiteDatabase, tableName: String, scheme: Scheme, query: String, queryParameters: [RelationValue]) {
        self.db = db
        self.tableName = tableName
        self.scheme = scheme
        self.query = query
        self.queryParameters = queryParameters
    }
    
    public func rows() -> AnyGenerator<Result<Row, RelationError>> {
        var queryGenerator: AnyGenerator<Result<Row, RelationError>>? = nil
        return AnyGenerator(body: {
            if let queryGenerator = queryGenerator {
                return queryGenerator.next()
            } else {
                let result = self.db.executeQuery("SELECT * FROM (\(self.query))", self.queryParameters)
                switch result {
                case .Ok(let generator):
                    queryGenerator = generator
                    return generator.next()
                case .Err(let error):
                    return .Err(error)
                }
            }
        })
    }
    
    public func contains(row: Row) -> Result<Bool, RelationError> {
        fatalError("unimplemented")
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
    
    public func select(terms: [ComparisonTerm]) -> Relation {
        if let (sql, parameters) = termsToSQL(terms) {
            return SQLiteRelation(db: db, tableName: self.tableName, scheme: scheme, query: "SELECT * FROM (\(self.query)) WHERE \(sql)", queryParameters: self.queryParameters + parameters)
        } else {
            return SelectRelation(relation: self, terms: terms)
        }
    }
}

public class SQLiteTableRelation: SQLiteRelation {
    init(db: SQLiteDatabase, tableName: String, scheme: Scheme) {
        super.init(db: db, tableName: tableName, scheme: scheme, query: db.escapeIdentifier(tableName), queryParameters: [])
    }
    
    public func add(row: Row) -> Result<Int64, RelationError> {
        if !db.tables.contains(tableName) {
            if let err = db.createRelation(tableName, scheme: scheme).err {
                return .Err(err)
            }
        }
        
        let orderedAttributes = Array(row.values)
        let attributesSQL = orderedAttributes.map({ db.escapeIdentifier($0.0.name) }).joinWithSeparator(", ")
        let parameters = orderedAttributes.map({ $0.1 })
        let valuesSQL = Array(count: orderedAttributes.count, repeatedValue: "?").joinWithSeparator(", ")
        let sql = "INSERT INTO \(tableNameForQuery) (\(attributesSQL)) VALUES (\(valuesSQL))"
        
        let result = db.executeQuery(sql, parameters)
        return result.map({ rows in
            let array = Array(rows)
            precondition(array.isEmpty, "Unexpected results from INSERT INTO statement: \(array)")
            return sqlite3_last_insert_rowid(db.db)
        })
    }
    
    public func delete(searchTerms: [ComparisonTerm]) -> Result<Void, RelationError> {
        if let (whereSQL, whereParameters) = termsToSQL(searchTerms) {
            let sql = "DELETE FROM \(tableNameForQuery) WHERE \(whereSQL)"
            let result = db.executeQuery(sql, whereParameters)
            return result.map({
                let array = Array($0)
                precondition(array.isEmpty, "Unexpected results from DELETE FROM statement: \(array)")
                return ()
            })
        } else {
            fatalError("Don't know how to transform these search terms into SQL, and we haven't implemented non-SQL deletes: \(searchTerms)")
        }
    }
    
    public func update(searchTerms: [ComparisonTerm], newValues: Row) -> Result<Void, RelationError> {
        if let (whereSQL, whereParameters) = termsToSQL(searchTerms) {
            let orderedAttributes = Array(newValues.values)
            let setParts = orderedAttributes.map({ db.escapeIdentifier($0.0.name) + " = ?" })
            let setSQL = setParts.joinWithSeparator(", ")
            let setParameters = orderedAttributes.map({ $0.1 })
            
            let sql = "UPDATE \(tableNameForQuery) SET \(setSQL) WHERE \(whereSQL)"
            let result = db.executeQuery(sql, setParameters + whereParameters)
            return result.map({
                let array = Array($0)
                precondition(array.isEmpty, "Unexpected results from UPDATE statement: \(array)")
                return ()
            })
        } else {
            fatalError("Don't know how to transform these search terms into SQL, and we haven't implemented non-SQL updates: \(searchTerms)")
        }
    }
}

