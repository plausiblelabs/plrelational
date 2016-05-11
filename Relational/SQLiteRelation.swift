
import sqlite3

public class SQLiteRelation: Relation, RelationDefaultChangeObserverImplementation {
    let db: SQLiteDatabase
    
    public let tableName: String
    public let scheme: Scheme
    
    public var changeObserverData = RelationDefaultChangeObserverImplementationData()
    
    var tableNameForQuery: String {
        return db.escapeIdentifier(tableName)
    }
    
    let queryTerms: [ComparisonTerm]
    
    init(db: SQLiteDatabase, tableName: String, scheme: Scheme, queryTerms: [ComparisonTerm]) {
        self.db = db
        self.tableName = tableName
        self.scheme = scheme
        self.queryTerms = queryTerms
        
        precondition(termsToSQL(queryTerms) != nil, "Query terms must be SQL compatible!")
    }
    
    public func rows() -> AnyGenerator<Result<Row, RelationError>> {
        var queryGenerator: AnyGenerator<Result<Row, RelationError>>? = nil
        return AnyGenerator(body: {
            if let queryGenerator = queryGenerator {
                return queryGenerator.next()
            } else {
                let (sql, parameters) = self.termsToSQL(self.queryTerms)!
                let result = self.db.executeQuery("SELECT * FROM (\(self.tableNameForQuery)) WHERE \(sql)", parameters)
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
        let terms = ComparisonTerm.termsFromRow(row)
        let selected = select(terms)
        let rowsResult = mapOk(selected.rows(), { $0 })
        return rowsResult.map({ !$0.isEmpty })
    }
    
    public func update(terms: [ComparisonTerm], newValues: Row) -> Result<Void, RelationError> {
        if let (whereSQL, whereParameters) = termsToSQL(terms + self.queryTerms) {
            let orderedAttributes = Array(newValues.values)
            let setParts = orderedAttributes.map({ db.escapeIdentifier($0.0.name) + " = ?" })
            let setSQL = setParts.joinWithSeparator(", ")
            let setParameters = orderedAttributes.map({ $0.1 })
            
            let sql = "UPDATE \(tableNameForQuery) SET \(setSQL) WHERE \(whereSQL)"
            let result = db.executeQuery(sql, setParameters + whereParameters)
            return result.map({
                let array = Array($0)
                precondition(array.isEmpty, "Unexpected results from UPDATE statement: \(array)")
                self.notifyChangeObservers([.Update(terms, newValues)])
                return ()
            })
        } else {
            fatalError("Don't know how to transform these search terms into SQL, and we haven't implemented non-SQL updates: \(terms)")
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
        // Special-case zero terms, because SQL doesn't like empty WHERE clauses
        if terms.count == 0 {
            return ("1", [])
        }
        
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
        if termsToSQL(terms) != nil {
            return SQLiteRelation(db: db, tableName: self.tableName, scheme: scheme, queryTerms: self.queryTerms + terms)
        } else {
            return SelectRelation(relation: self, terms: terms)
        }
    }
}

public class SQLiteTableRelation: SQLiteRelation {
    init(db: SQLiteDatabase, tableName: String, scheme: Scheme) {
        super.init(db: db, tableName: tableName, scheme: scheme, queryTerms: [])
    }
    
    public func add(row: Row) -> Result<Int64, RelationError> {
        let orderedAttributes = Array(row.values)
        let attributesSQL = orderedAttributes.map({ db.escapeIdentifier($0.0.name) }).joinWithSeparator(", ")
        let parameters = orderedAttributes.map({ $0.1 })
        let valuesSQL = Array(count: orderedAttributes.count, repeatedValue: "?").joinWithSeparator(", ")
        let sql = "INSERT INTO \(tableNameForQuery) (\(attributesSQL)) VALUES (\(valuesSQL))"
        
        let result = db.executeQuery(sql, parameters)
        return result.map({ rows in
            let array = Array(rows)
            precondition(array.isEmpty, "Unexpected results from INSERT INTO statement: \(array)")
            let rowid = sqlite3_last_insert_rowid(db.db)
            self.notifyChangeObservers([.Add(row)])
            return rowid
        })
    }
    
    public func delete(searchTerms: [ComparisonTerm]) -> Result<Void, RelationError> {
        if let (whereSQL, whereParameters) = termsToSQL(searchTerms) {
            let sql = "DELETE FROM \(tableNameForQuery) WHERE \(whereSQL)"
            let result = db.executeQuery(sql, whereParameters)
            return result.map({
                let array = Array($0)
                precondition(array.isEmpty, "Unexpected results from DELETE FROM statement: \(array)")
                self.notifyChangeObservers([.Delete(searchTerms)])
                return ()
            })
        } else {
            fatalError("Don't know how to transform these search terms into SQL, and we haven't implemented non-SQL deletes: \(searchTerms)")
        }
    }
}

