//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation


open class TransactionalDatabase {
    let changeLoggingDatabase: ChangeLoggingDatabase
    
    var inTransaction = false
    
    var relations: [String: TransactionalRelation] = [:]
    
    let readWriteLock = RWLock()
    let transactionLock = NSLock()
    
    var currentTransactionThread: pthread_t? = nil
    
    var transactionCounter: UInt64 = 0
    
    public init(_ db: ChangeLoggingDatabase) {
        self.changeLoggingDatabase = db
    }
    
    public convenience init(_ db: SQLiteDatabase) {
        self.init(ChangeLoggingDatabase(db))
    }
    
    open subscript(name: String) -> TransactionalRelation {
        if let r = relations[name] {
            return r
        } else {
            let r = TransactionalRelation(db: self, underlyingRelation: changeLoggingDatabase[name])
            if inTransaction {
                self.beginTransactionForRelation(r)
            }
            relations[name] = r
            return r
        }
    }
    
    open func lockReading() {
        readWriteLock.readLock()
    }
    
    open func unlockReading() {
        readWriteLock.unlock()
    }
    
    open func beginTransaction() {
        transactionLock.lock()
        
        precondition(!inTransaction, "We don't do nested transactions (yet?)")
        
        for (_, r) in relations {
            self.beginTransactionForRelation(r)
        }
        
        currentTransactionThread = pthread_self()
        inTransaction = true
    }
    
    func beginTransactionForRelation(_ r: TransactionalRelation) {
        r.transactionRelation = r.underlyingRelation.deriveChangeLoggingRelation()
    }
    
    open func endTransaction() -> Result<Void, RelationError> {
        precondition(inTransaction, "Can't end transaction when we're not in one")
        
        var changes: [(TransactionalRelation, RelationChange)] = []
        
        let result: Result<Void, RelationError> = readWriteLock.write({
            for (_, r) in relations {
                let result = endTransactionForRelation(r)
                switch result {
                case .Ok(let change):
                    changes.append((r, change))
                case .Err(let err):
                    return .Err(err)
                }
            }
            
            inTransaction = false
            currentTransactionThread = nil
            transactionCounter += 1
            transactionLock.unlock()
            
            return .Ok()
        })
        
        if result.ok != nil {
            for (r, _) in changes {
                r.notifyObserversTransactionBegan(.directChange)
            }
            
            for (r, change) in changes {
                r.notifyChangeObservers(change, kind: .directChange)
            }
            
            for (r, _) in changes {
                r.notifyObserversTransactionEnded(.directChange)
            }
        }
        
        return result
    }
    
    func endTransactionForRelation(_ r: TransactionalRelation) -> Result<RelationChange, RelationError> {
        // In computing the change log, we're assuming that target hasn't been changed.
        // Right now we don't support directly changing the database during a transaction.
        // If we ever do, it would involve retrying the transaction so this should still hold.
        let underlying = r.underlyingRelation
        let transaction = r.transactionRelation!
        
        r.transactionRelation = nil
        return underlying.restoreFromChangeLoggingRelation(transaction)
    }
    
    open func takeSnapshot() -> TransactionalDatabaseSnapshot {
        let snapshots = relations.values.map({ ($0, $0.takeSnapshot()) })
        return TransactionalDatabaseSnapshot(relationSnapshots: Array(snapshots))
    }
    
    open func restoreSnapshot(_ snapshot: TransactionalDatabaseSnapshot) -> Result<Void, RelationError> {
        precondition(!inTransaction, "Can't restore a snapshot while in a transaction")
        
        for (_, r) in relations {
            r.notifyObserversTransactionBegan(.directChange)
        }
        
        defer {
            for (_, r) in relations {
                r.notifyObserversTransactionEnded(.directChange)
            }
        }
        
        var changes: [(TransactionalRelation, RelationChange)] = []
        
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
        for relation in relations.values {
            if !snapshottedRelations.contains(ObjectIdentifier(relation)) {
                let change = relation.rawRestoreSnapshot(ChangeLoggingRelationSnapshot(bookmark: relation.underlyingRelationForQueryExecution.baseBookmark))
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
    
    open func asyncRestoreSnapshot(_ snapshot: TransactionalDatabaseSnapshot) {
        AsyncManager.currentInstance.registerRestoreSnapshot(self, snapshot: snapshot)
    }
    
    open func computeDelta(from: TransactionalDatabaseSnapshot, to: TransactionalDatabaseSnapshot) -> TransactionalDatabaseDelta {
        let fromDict = ObjectDictionary(from.relationSnapshots)
        
        let result = to.relationSnapshots.map({ relation, toSnapshot -> (TransactionalRelation, ChangeLoggingRelationDelta) in
            let fromSnapshot = fromDict[relation] ?? ChangeLoggingRelationSnapshot(bookmark: relation.underlyingRelationForQueryExecution.zeroBookmark)
            let delta = relation.computeDelta(from: fromSnapshot, to: toSnapshot)
            return (relation, delta)
        })
        return .init(relationDeltas: result)
    }
    
    open func apply(delta: TransactionalDatabaseDelta) -> Result<Void, RelationError> {
        for (relation, delta) in delta.relationDeltas {
            let result = relation.apply(delta: delta)
            if case .Err = result {
                return result
            }
        }
        return .Ok()
    }
    
    open func asyncApply(delta: TransactionalDatabaseDelta) {
        AsyncManager.currentInstance.registerApplyDelta(self, delta: delta)
    }
    
    open func transaction(_ transactionFunction: (Void) -> Void) {
        beginTransaction()
        transactionFunction()
        // TODO: error checking?
        _ = endTransaction()
    }
    
    open func transactionWithSnapshots(_ transactionFunction: (Void) -> Void) -> (before: TransactionalDatabaseSnapshot, after: TransactionalDatabaseSnapshot) {
        let before = takeSnapshot()
        transaction(transactionFunction)
        let after = takeSnapshot()
        return (before, after)
    }
    
    fileprivate var inTransactionThread: Bool {
        return currentTransactionThread == pthread_self()
    }
}

public class TransactionalRelation: MutableRelation, RelationDefaultChangeObserverImplementation {
    weak var db: TransactionalDatabase?
    var underlyingRelation: ChangeLoggingRelation
    var transactionRelation: ChangeLoggingRelation?
    
    open var changeObserverData = RelationDefaultChangeObserverImplementationData()
    
    init(db: TransactionalDatabase, underlyingRelation: ChangeLoggingRelation) {
        self.db = db
        self.underlyingRelation = underlyingRelation
        underlyingRelation.addWeakChangeObserver(self, method: type(of: self).observeUnderlyingChange)
    }
    
    open var scheme: Scheme {
        return underlyingRelation.scheme
    }
    
    open var contentProvider: RelationContentProvider {
        return .underlying(underlyingRelationForQueryExecution)
    }
    
    open var underlyingRelationForQueryExecution: ChangeLoggingRelation {
        if let db = db , !db.inTransactionThread {
            return underlyingRelation
        } else {
            return (transactionRelation ?? underlyingRelation)
        }
    }
    
    open func contains(_ row: Row) -> Result<Bool, RelationError> {
        return underlyingRelationForQueryExecution.contains(row)
    }
    
    open func add(_ row: Row) -> Result<Int64, RelationError> {
        return wrapInTransactionIfNecessary({
            (transactionRelation ?? underlyingRelation).add(row)
        })
    }
    
    open func delete(_ query: SelectExpression) -> Result<Void, RelationError> {
        return wrapInTransactionIfNecessary({
            (transactionRelation ?? underlyingRelation).delete(query)
        })
    }
    
    open func update(_ query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        return wrapInTransactionIfNecessary({
            (transactionRelation ?? underlyingRelation).update(query, newValues: newValues)
        })
    }
    
    func observeUnderlyingChange(_ change: RelationChange) {
        self.notifyChangeObservers(change, kind: .directChange)
    }
    
    func wrapInTransactionIfNecessary<T>(_ f: (Void) -> T) -> T {
        if let db = db , !db.inTransactionThread {
            db.beginTransaction()
            defer { _ = db.endTransaction() } // TODO: error handling?
            return f()
        } else {
            return f()
        }
    }
}

extension TransactionalRelation {
    public func takeSnapshot() -> ChangeLoggingRelationSnapshot {
        return underlyingRelationForQueryExecution.takeSnapshot()
    }
    
    public func rawRestoreSnapshot(_ snapshot: ChangeLoggingRelationSnapshot) -> Result<RelationChange, RelationError> {
        return underlyingRelationForQueryExecution.rawRestoreSnapshot(snapshot)
    }
    
    public func computeDelta(from: ChangeLoggingRelationSnapshot, to: ChangeLoggingRelationSnapshot) -> ChangeLoggingRelationDelta {
        return underlyingRelationForQueryExecution.computeDelta(from: from, to: to)
    }
    
    public func apply(delta: ChangeLoggingRelationDelta) -> Result<Void, RelationError> {
        return underlyingRelationForQueryExecution.apply(delta: delta)
    }
}

public struct TransactionalDatabaseSnapshot {
    var relationSnapshots: [(TransactionalRelation, ChangeLoggingRelationSnapshot)]
}

public struct TransactionalDatabaseDelta {
    var relationDeltas: [(TransactionalRelation, ChangeLoggingRelationDelta)]
    
    public var reversed: TransactionalDatabaseDelta {
        return .init(relationDeltas: relationDeltas.map({
            ($0, $1.reversed)
        }))
    }
}

extension TransactionalDatabase {
    public func dump() {
        for r in relations.values {
            print(r)
        }
    }
}
