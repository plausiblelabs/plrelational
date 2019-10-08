//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import sqlite3

open class SQLiteRelation: Relation, RelationDefaultChangeObserverImplementation {
    let db: SQLiteDatabase
    
    public let tableName: String
    public let scheme: Scheme
    
    open var changeObserverData = RelationDefaultChangeObserverImplementationData()
    
    public var debugName: String?
    
    var tableNameForQuery: String {
        return db.escapeIdentifier(tableName)
    }
    
    /// The query that this relation performs on the underlying table.
    /// If nil, then it represents the entire table.
    let query: SelectExpression?
    
    init(db: SQLiteDatabase, tableName: String, scheme: Scheme, query: SelectExpression?) {
        self.db = db
        self.tableName = tableName
        self.scheme = scheme
        self.query = query
        
        LogRelationCreation(self)
        precondition(queryToSQL(query) != nil, "Query terms must be SQL compatible!")
    }
    
    fileprivate func rawGenerateRows() -> AnyIterator<Result<Set<Row>, RelationError>> {
        let data = LogRelationIterationBegin(self)
        var queryGenerator: AnyIterator<Result<Row, RelationError>>? = nil
        return LogRelationIterationReturn(data, AnyIterator({
            if let queryGenerator = queryGenerator {
                return queryGenerator.next()?.map({ [$0] })
            } else {
                let (sql, parameters) = self.queryToSQL(self.query)!
                let result = self.db.executeQuery("SELECT * FROM (\(self.tableNameForQuery)) WHERE \(sql)", parameters)
                switch result {
                case .Ok(let generator):
                    queryGenerator = generator
                    return generator.next()?.map({ [$0] })
                case .Err(let error):
                    return .Err(error)
                }
            }
        }))
    }
    
    open var contentProvider: RelationContentProvider {
        return .generator({ self.rawGenerateRows() }, approximateCount: nil)
    }
    
    open func contains(_ row: Row) -> Result<Bool, RelationError> {
        let query = SelectExpressionFromRow(row)
        let selected = select(query)
        let rowsResult = mapOk(selected.rows(), { $0 })
        return rowsResult.map({ !$0.isEmpty })
    }
    
    open func update(_ query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        let baseTable = db[tableName]!
        return baseTable.update(self.queryAndedWithOtherQuery(query), newValues: newValues)
    }
    
    open func onAddFirstObserver() {
        let baseTable = db[tableName]!
        baseTable.addWeakChangeObserver(self, call: {
            $0.notifyChangeObservers($1, kind: .directChange)
        })
    }
}

extension SQLiteRelation {
    fileprivate func operatorToSQL(_ op: BinaryOperator) -> String? {
        switch op {
        case is EqualityComparator:
            return "="
        case is AndComparator:
            return "AND"
        case is OrComparator:
            return "OR"
        case is GlobComparator:
            return "GLOB"
        default:
            return nil
        }
    }
    
    fileprivate func operatorToSQL(_ op: UnaryOperator) -> String? {
        switch op {
        case is NotOperator:
            return "NOT"
        default:
            return nil
        }
    }
    
    fileprivate func queryToSQL(_ query: SelectExpression?) -> (String, [RelationValue])? {
        switch query {
        case nil:
            return ("1", [])
        case let value as RelationValue:
            return ("?", [value])
        case let value as Attribute:
            return (db.escapeIdentifier(value.name), [])
        case let value as Bool:
            return (value ? "1" : "0", [])
        case let value as String:
            return ("?", [RelationValue(value)])
        case let value as Int:
            return ("?", [RelationValue(Int64(value))])
        case let value as SelectExpressionBinaryOperator:
            if let
                lhs = queryToSQL(value.lhs),
                let opSQL = operatorToSQL(value.op),
                let rhs = queryToSQL(value.rhs) {
                return ("(\(lhs.0)) \(opSQL) (\(rhs.0))", lhs.1 + rhs.1)
            }
        case let value as SelectExpressionUnaryOperator:
            if let
                opSQL = operatorToSQL(value.op),
                let expr = queryToSQL(value.expr) {
                return ("\(opSQL) (\(expr.0))", expr.1)
            }
        default:
            break
        }
        return nil
    }
    
    /// Return self.query ANDed with another query. If self.query is nil,
    /// returns the other query directly.
    fileprivate func queryAndedWithOtherQuery(_ otherQuery: SelectExpression) -> SelectExpression {
        if let myQuery = self.query {
            return myQuery *&& otherQuery
        } else {
            return otherQuery
        }
    }
    
    public func select(_ query: SelectExpression) -> Relation {
        // Short circuit when the query is a simple true, just for useless efficiency.
        if let query = query as? RelationValue , query.boolValue == true {
            return self
        } else if queryToSQL(query) != nil {
            return SQLiteRelation(db: db, tableName: self.tableName, scheme: scheme, query: self.queryAndedWithOtherQuery(query))
        } else {
            return IntermediateRelation(op: .select(query), operands: [self])
        }
    }
}

open class SQLiteTableRelation: SQLiteRelation, StoredRelation {
    init(db: SQLiteDatabase, tableName: String, scheme: Scheme) {
        super.init(db: db, tableName: tableName, scheme: scheme, query: nil)
    }
    
    open override func onAddFirstObserver() {
        // If we're the original, base table then we have nothing to do.
    }
    
    open func add(_ row: Row) -> Result<Int64, RelationError> {
        let orderedAttributes = Array(row)
        let attributesSQL = orderedAttributes.map({ db.escapeIdentifier($0.0.name) }).joined(separator: ", ")
        let parameters = orderedAttributes.map({ $0.1 })
        let valuesSQL = Array(repeating: "?", count: orderedAttributes.count).joined(separator: ", ")
        let sql = "INSERT INTO \(tableNameForQuery) (\(attributesSQL)) VALUES (\(valuesSQL))"
        
        let result = db.executeQuery(sql, parameters)
        return result.then({ rows in
            let array = Array(rows)
            if let error = array.first?.err {
                return .Err(error)
            }
            
            precondition(array.isEmpty, "Unexpected results from INSERT INTO statement: \(array)")
            let rowid = sqlite3_last_insert_rowid(db.db)
            self.notifyChangeObservers(RelationChange(added: ConcreteRelation(row), removed: nil), kind: .directChange)
            return .Ok(rowid)
        })
    }

    open func delete(_ query: SelectExpression) -> Result<Void, RelationError> {
        if let (whereSQL, whereParameters) = queryToSQL(query) {
            let willDelete = ConcreteRelation.copyRelation(self.select(query))
            return willDelete.then({ willDelete in
                let sql = "DELETE FROM \(tableNameForQuery) WHERE \(whereSQL)"
                let result = db.executeQuery(sql, whereParameters)
                return result.then({ rows in
                    let array = Array(rows)
                    if let error = array.first?.err {
                        return .Err(error)
                    }
                    
                    precondition(array.isEmpty, "Unexpected results from DELETE FROM statement: \(array)")
                    self.notifyChangeObservers(RelationChange(added: nil, removed: willDelete), kind: .directChange)
                    
                    return .Ok(())
                })
            })
        } else {
            fatalError("Don't know how to transform these search terms into SQL, and we haven't implemented non-SQL deletes: \(query)")
        }
    }
    
    override open func update(_ query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        if let (whereSQL, whereParameters) = queryToSQL(self.queryAndedWithOtherQuery(query)) {
            let willUpdate = ConcreteRelation.copyRelation(self.select(query))
            return willUpdate.then({ willUpdate in
                let orderedAttributes = Array(newValues)
                let setParts = orderedAttributes.map({ db.escapeIdentifier($0.0.name) + " = ?" })
                let setSQL = setParts.joined(separator: ", ")
                let setParameters = orderedAttributes.map({ $0.1 })
                
                let sql = "UPDATE \(tableNameForQuery) SET \(setSQL) WHERE \(whereSQL)"
                let result = db.executeQuery(sql, setParameters + whereParameters)
                return result.then({ rows in
                    let array = Array(rows)
                    if let error = array.first?.err {
                        return .Err(error)
                    }
                    
                    precondition(array.isEmpty, "Unexpected results from UPDATE statement: \(array)")
                    
                    let updated = willUpdate.withUpdate(newValues)
                    self.notifyChangeObservers(RelationChange(added: updated, removed: willUpdate), kind: .directChange)
                    return .Ok(())
                })
            })
        } else {
            fatalError("Don't know how to transform these search terms into SQL, and we haven't implemented non-SQL updates: \(query)")
        }
    }
}

