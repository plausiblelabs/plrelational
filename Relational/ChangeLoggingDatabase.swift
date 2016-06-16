//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

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
            let relation = ChangeLoggingRelation(baseRelation: table)
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
                let originalRelation = db.getLoggingRelation(name)
                let relation = originalRelation.deriveChangeLoggingRelation()
                changeLoggingRelations[name] = relation
                return relation
            }
        }
    }
    
    public func transaction(transactionFunction: Transaction -> Void) -> Result<Void, RelationError> {
        let transaction = Transaction(db: self)
        
        transactionFunction(transaction)
        
        var changes: [(ChangeLoggingRelation<SQLiteTableRelation>, RelationChange)] = []
        for (name, relation) in transaction.changeLoggingRelations {
            let target = self[name]
            // This snapshot thing is kind of elegant and ugly at the same time. It gets the job done
            // of applying the new state and retrieving the changes, anyway.
            let pretendSnapshot = relation.takeSnapshot()
            let result = target.rawRestoreSnapshot(pretendSnapshot)
            switch result {
            case .Ok(let relationChanges):
                changes.append((target, relationChanges))
            case .Err(let err):
                return .Err(err)
            }
        }
        
        for (relation, _) in changes {
            relation.notifyObserversTransactionBegan(.DirectChange)
        }
        
        for (relation, change) in changes {
            relation.notifyChangeObservers(change, kind: .DirectChange)
        }
        
        for (relation, _) in changes {
            relation.notifyObserversTransactionEnded(.DirectChange)
        }

        return .Ok()
    }
}

extension ChangeLoggingDatabase {
    public func takeSnapshot() -> ChangeLoggingDatabaseSnapshot {
        let relationSnapshots = changeLoggingRelations.values.map({ ($0, $0.takeSnapshot()) })
        return ChangeLoggingDatabaseSnapshot(relationSnapshots: Array(relationSnapshots))
    }
    
    public func restoreSnapshot(snapshot: ChangeLoggingDatabaseSnapshot) -> Result<Void, RelationError> {
        var changes: [(ChangeLoggingRelation<SQLiteTableRelation>, RelationChange)] = []
        
        // Restore all the snapshotted relations.
        for (relation, snapshot) in snapshot.relationSnapshots {
            let change = relation.rawRestoreSnapshot(snapshot)
            switch change {
            case .Ok(let change):
                changes.append((relation, change))
            case .Err(let err):
                return .Err(err)
            }
        }
        
        // Any relations that were created after the snapshot was taken won't be captured.
        // Figure out what those are, if any, and restore them to emptiness. This is sorta ugly!
        let snapshottedRelations = Set(snapshot.relationSnapshots.map({ ObjectIdentifier($0.0) }))
        for (_, relation) in changeLoggingRelations {
            if !snapshottedRelations.contains(ObjectIdentifier(relation)) {
                let change = relation.rawRestoreSnapshot(ChangeLoggingRelationSnapshot(savedLog: []))
                switch change {
                case .Ok(let change):
                    changes.append((relation, change))
                case .Err(let err):
                    return .Err(err)
                }
            }
        }
        
        for (relation, change) in changes {
            relation.notifyChangeObservers(change, kind: .DirectChange)
        }
        
        return .Ok()
    }
    
    /// A wrapper function that performs a transaction and provides before and after snapshots to the caller.
    public func transactionWithSnapshots(transactionFunction: Transaction -> Void) -> (before: ChangeLoggingDatabaseSnapshot, after: ChangeLoggingDatabaseSnapshot) {
        let before = takeSnapshot()
        transaction(transactionFunction)
        let after = takeSnapshot()
        return (before, after)
    }
}
