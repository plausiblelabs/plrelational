
public struct ChangeLoggingDatabaseSnapshot {
    var relationSnapshots: [(ChangeLoggingRelation<SQLiteTableRelation>, ChangeLoggingRelationSnapshot)]
}

public class ChangeLoggingDatabase {
    let sqliteDatabase: SQLiteDatabase
    
    var changeLoggingRelations: [String: ChangeLoggingRelation<SQLiteTableRelation>] = [:]
    
    public init(_ db: SQLiteDatabase) {
        self.sqliteDatabase = db
    }
    
    public subscript(name: String) -> ChangeLoggingRelation<SQLiteTableRelation> {
        return getLoggingRelation(name)
    }
    
    public func save() -> Result<Void, RelationError> {
        return sqliteDatabase.transaction({
            for (_, relation) in changeLoggingRelations {
                let result = relation.save()
                if let err = result.err {
                    return (.Err(err), .Rollback)
                }
            }
            return (.Ok(), .Commit)
        }).then({ $0 })
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
        private var changeLoggingRelations: [String: ChangeLoggingRelation<SQLiteTableRelation>] = [:]
        
        private init(db: ChangeLoggingDatabase) {
            self.db = db
        }
        
        public subscript(name: String) -> ChangeLoggingRelation<SQLiteTableRelation> {
            if let relation = changeLoggingRelations[name] {
                return relation
            } else {
                let table = db.getLoggingRelation(name)
                let relation = ChangeLoggingRelation(underlyingRelation: table.underlyingRelation)
                relation.log = table.log
                changeLoggingRelations[name] = relation
                return relation
            }
        }
    }
    
    public func transaction(transactionFunction: Transaction -> Void) {
        let transaction = Transaction(db: self)
        
        transactionFunction(transaction)
        
        var changes: [(ChangeLoggingRelation<SQLiteTableRelation>, RelationChange)] = []
        for (name, relation) in transaction.changeLoggingRelations {
            let target = self[name]
            // In computing the change log, we're assuming that target hasn't been changed.
            // Right now we don't support directly changing the database during a transaction.
            // If we ever do, it would involve retrying the transaction so this should still hold.
            
            let newLog = relation.log[target.log.count ..< relation.log.count]
            let change = target.dynamicType.computeChangeFromLog(newLog, underlyingRelation: target.computeFinalRelation())
            changes.append((target, change))
            
            target.log = relation.log
        }
        
        for (relation, change) in changes {
            relation.notifyChangeObservers(change)
        }
    }
}

extension ChangeLoggingDatabase {
    public func takeSnapshot() -> ChangeLoggingDatabaseSnapshot {
        let relationSnapshots = changeLoggingRelations.values.map({ ($0, $0.takeSnapshot()) })
        return ChangeLoggingDatabaseSnapshot(relationSnapshots: Array(relationSnapshots))
    }
    
    public func restoreSnapshot(snapshot: ChangeLoggingDatabaseSnapshot) {
        // Restore all the snapshotted relations.
        for (relation, snapshot) in snapshot.relationSnapshots {
            relation.restoreSnapshot(snapshot, notifyObservers: false)
        }
        
        // Any relations that were created after the snapshot was taken won't be captured.
        // Figure out what those are, if any, and restore them to emptiness. This is sorta ugly!
        let snapshottedRelations = Set(snapshot.relationSnapshots.map({ ObjectIdentifier($0.0) }))
        for (_, relation) in changeLoggingRelations {
            if !snapshottedRelations.contains(ObjectIdentifier(relation)) {
                relation.restoreEmptySnapshot(notifyObservers: false)
            }
        }
        
        for (_, relation) in changeLoggingRelations {
            // XXX TODO: we need to provide the actual changes here!
            relation.notifyChangeObservers(RelationChange(added: nil, removed: nil))
        }
    }
    
    /// A wrapper function that performs a transaction and provides before and after snapshots to the caller.
    public func transactionWithSnapshots(transactionFunction: Transaction -> Void) -> (before: ChangeLoggingDatabaseSnapshot, after: ChangeLoggingDatabaseSnapshot) {
        let before = takeSnapshot()
        transaction(transactionFunction)
        let after = takeSnapshot()
        return (before, after)
    }
}
