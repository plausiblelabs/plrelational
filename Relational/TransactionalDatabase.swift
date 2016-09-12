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
    
    open func takeSnapshot() -> ChangeLoggingDatabaseSnapshot {
        return changeLoggingDatabase.takeSnapshot()
    }
    
    open func restoreSnapshot(_ snapshot: ChangeLoggingDatabaseSnapshot) {
        precondition(!inTransaction, "Can't restore a snapshot while in a transaction")
        
        for (_, r) in relations {
            r.notifyObserversTransactionBegan(.directChange)
        }
        
        // TODO: error checking?
        _ = changeLoggingDatabase.restoreSnapshot(snapshot)
        
        for (_, r) in relations {
            r.notifyObserversTransactionEnded(.directChange)
        }
    }
    
    open func asyncRestoreSnapshot(_ snapshot: ChangeLoggingDatabaseSnapshot) {
        UpdateManager.currentInstance.registerRestoreSnapshot(self, snapshot: snapshot)
    }
    
    open func transaction(_ transactionFunction: (Void) -> Void) {
        beginTransaction()
        transactionFunction()
        // TODO: error checking?
        _ = endTransaction()
    }
    
    open func transactionWithSnapshots(_ transactionFunction: (Void) -> Void) -> (before: ChangeLoggingDatabaseSnapshot, after: ChangeLoggingDatabaseSnapshot) {
        let before = takeSnapshot()
        transaction(transactionFunction)
        let after = takeSnapshot()
        return (before, after)
    }
    
    fileprivate var inTransactionThread: Bool {
        return currentTransactionThread == pthread_self()
    }
}

public extension TransactionalDatabase {
    public class TransactionalRelation: MutableRelation, RelationDefaultChangeObserverImplementation {
        weak var db: TransactionalDatabase?
        var underlyingRelation: ChangeLoggingRelation<SQLiteTableRelation>
        var transactionRelation: ChangeLoggingRelation<SQLiteTableRelation>?
        
        open var changeObserverData = RelationDefaultChangeObserverImplementationData()
        
        init(db: TransactionalDatabase, underlyingRelation: ChangeLoggingRelation<SQLiteTableRelation>) {
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
        
        open var underlyingRelationForQueryExecution: Relation {
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
}

// This ought to go in UpdateManager.swift but the compiler barfs on it there for some reason.
public extension TransactionalDatabase.TransactionalRelation {
    func asyncAdd(_ row: Row) {
        UpdateManager.currentInstance.registerAdd(self, row: row)
    }
    
    func asyncDelete(_ query: SelectExpression) {
        UpdateManager.currentInstance.registerDelete(self, query: query)
    }
}
