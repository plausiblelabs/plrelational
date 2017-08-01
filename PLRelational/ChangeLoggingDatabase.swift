//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

/// :nodoc:
public struct ChangeLoggingDatabaseSnapshot {
    var relationSnapshots: [(ChangeLoggingRelation, ChangeLoggingRelationSnapshot)]
}

/// :nodoc:
public struct ChangeLoggingDatabaseDelta {
    var relationDeltas: [(ChangeLoggingRelation, ChangeLoggingRelationDelta)]
    
    public var reversed: ChangeLoggingDatabaseDelta {
        return ChangeLoggingDatabaseDelta(relationDeltas: relationDeltas.map({
            ($0, $1.reversed)
        }))
    }
}

public class ChangeLoggingDatabase {
    fileprivate let storedDatabase: StoredDatabase
    
    fileprivate var changeLoggingRelations: [String: ChangeLoggingRelation] = [:]
    
    public init(_ db: StoredDatabase) {
        self.storedDatabase = db
    }
    
    public subscript(name: String) -> ChangeLoggingRelation {
        return getLoggingRelation(name)
    }
    
    public func save() -> Result<Void, RelationError> {
        return storedDatabase.transaction({
            for (_, relation) in changeLoggingRelations {
                let result = relation.save()
                if storedDatabase.resultNeedsRetry(result) {
                    return (.Ok(), .retry)
                }
                if let err = result.err {
                    return (.Err(err), .rollback)
                }
            }
            return (.Ok(), .commit)
        }).then({ $0 })
    }
}

extension ChangeLoggingDatabase {
    fileprivate func getLoggingRelation(_ name: String) -> ChangeLoggingRelation {
        if let relation = changeLoggingRelations[name] {
            return relation
        } else {
            let storedRelation = storedDatabase.storedRelation(forName: name)!
            let relation = ChangeLoggingRelation(baseRelation: storedRelation)
            changeLoggingRelations[name] = relation
            return relation
        }
    }
}

extension ChangeLoggingDatabase {
    public class Transaction {
        fileprivate let db: ChangeLoggingDatabase
        fileprivate var changeLoggingRelations: [String: ChangeLoggingRelation] = [:]
        
        fileprivate init(db: ChangeLoggingDatabase) {
            self.db = db
        }
        
        public subscript(name: String) -> ChangeLoggingRelation {
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
    
    public func transaction(_ transactionFunction: (Transaction) -> Void) -> Result<Void, RelationError> {
        let transaction = Transaction(db: self)
        
        transactionFunction(transaction)
        
        var changes: [(ChangeLoggingRelation, RelationChange)] = []
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
            relation.notifyObserversTransactionBegan(.directChange)
        }
        
        for (relation, change) in changes {
            relation.notifyChangeObservers(change, kind: .directChange)
        }
        
        for (relation, _) in changes {
            relation.notifyObserversTransactionEnded(.directChange)
        }

        return .Ok()
    }
}

extension ChangeLoggingDatabase {
    public func takeSnapshot() -> ChangeLoggingDatabaseSnapshot {
        let relationSnapshots = changeLoggingRelations.values.map({ ($0, $0.takeSnapshot()) })
        return ChangeLoggingDatabaseSnapshot(relationSnapshots: Array(relationSnapshots))
    }
    
    public func restoreSnapshot(_ snapshot: ChangeLoggingDatabaseSnapshot) -> Result<Void, RelationError> {
        var changes: [(ChangeLoggingRelation, RelationChange)] = []
        
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
                let change = relation.rawRestoreSnapshot(ChangeLoggingRelationSnapshot(bookmark: relation.baseBookmark))
                switch change {
                case .Ok(let change):
                    changes.append((relation, change))
                case .Err(let err):
                    return .Err(err)
                }
            }
        }
        
        for (relation, change) in changes {
            relation.notifyChangeObservers(change, kind: .directChange)
        }
        
        return .Ok()
    }
    
    /// A wrapper function that performs a transaction and provides before and after snapshots to the caller.
    public func transactionWithSnapshots(_ transactionFunction: (Transaction) -> Void) -> (before: ChangeLoggingDatabaseSnapshot, after: ChangeLoggingDatabaseSnapshot) {
        let before = takeSnapshot()
        // TODO: error handling?
        _ = transaction(transactionFunction)
        let after = takeSnapshot()
        return (before, after)
    }
    
    public func computeDelta(from: ChangeLoggingDatabaseSnapshot, to: ChangeLoggingDatabaseSnapshot) -> ChangeLoggingDatabaseDelta {
        let fromDict = ObjectDictionary(from.relationSnapshots)
        
        let result = to.relationSnapshots.map({ relation, toSnapshot -> (ChangeLoggingRelation, ChangeLoggingRelationDelta) in
            let fromSnapshot = fromDict[relation] ?? ChangeLoggingRelationSnapshot(bookmark: relation.zeroBookmark)
            let delta = relation.computeDelta(from: fromSnapshot, to: toSnapshot)
            return (relation, delta)
        })
        return ChangeLoggingDatabaseDelta(relationDeltas: result)
    }
    
    public func apply(delta: ChangeLoggingDatabaseDelta) -> Result<Void, RelationError> {
        for (relation, delta) in delta.relationDeltas {
            let result = relation.apply(delta: delta)
            if case .Err = result {
                return result
            }
        }
        return .Ok()
    }
}
