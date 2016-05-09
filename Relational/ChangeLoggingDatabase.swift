
public class ChangeLoggingDatabase {
    let sqliteDatabase: SQLiteDatabase
    
    var changeLoggingRelations: [String: ChangeLoggingRelation<SQLiteTableRelation>] = [:]
    
    public init(_ db: SQLiteDatabase) {
        self.sqliteDatabase = db
    }
    
    public func createRelation(name: String, scheme: Scheme) -> Result<Void, RelationError> {
        return sqliteDatabase.createRelation(name, scheme: scheme).map({ _ in })
    }
    
    public subscript(name: String) -> Relation {
        return getLoggingRelation(name)
    }
    
    public func save() -> Result<Void, RelationError> {
        // TODO: transactions!
        for (_, relation) in changeLoggingRelations {
            let result = relation.save()
            if let err = result.err {
                return .Err(err)
            }
        }
        return .Ok()
    }
}

extension ChangeLoggingDatabase {
    private func getLoggingRelation(name: String) -> ChangeLoggingRelation<SQLiteTableRelation> {
        if let relation = changeLoggingRelations[name] {
            return relation
        } else {
            let table = sqliteDatabase[name]!
            let relation = ChangeLoggingRelation(underlyingRelation: table)
            changeLoggingRelations[name] = relation
            return relation
        }
    }
}

extension ChangeLoggingDatabase {
    public class Transaction {
        private let db: ChangeLoggingDatabase
        private var changeLoggingRelations: [String: ChangeLoggingRelation<ChangeLoggingRelation<SQLiteTableRelation>>] = [:]
        
        private init(db: ChangeLoggingDatabase) {
            self.db = db
        }
        
        public subscript(name: String) -> ChangeLoggingRelation<ChangeLoggingRelation<SQLiteTableRelation>> {
            if let relation = changeLoggingRelations[name] {
                return relation
            } else {
                let table = db.getLoggingRelation(name)
                let relation = ChangeLoggingRelation(underlyingRelation: table)
                changeLoggingRelations[name] = relation
                return relation
            }
        }
    }
    
    public func transaction(transactionFunction: Transaction -> Void) {
        let transaction = Transaction(db: self)
        
        transactionFunction(transaction)
        
        for (_, relation) in transaction.changeLoggingRelations {
            relation.underlyingRelation.log.appendContentsOf(relation.log)
        }
        for (_, relation) in transaction.changeLoggingRelations {
            relation.notifyChangeObservers()
        }
    }
}
