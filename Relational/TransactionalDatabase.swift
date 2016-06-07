
public class TransactionalDatabase {
    let changeLoggingDatabase: ChangeLoggingDatabase
    
    var inTransaction = false
    
    var relations: [String: TransactionalRelation] = [:]
    
    public init(_ db: ChangeLoggingDatabase) {
        self.changeLoggingDatabase = db
    }
    
    public convenience init(_ db: SQLiteDatabase) {
        self.init(ChangeLoggingDatabase(db))
    }
    
    public subscript(name: String) -> TransactionalRelation {
        if let r = relations[name] {
            return r
        } else {
            let r = TransactionalRelation(underlyingRelation: changeLoggingDatabase[name])
            if inTransaction {
                self.beginTransactionForRelation(r)
            }
            relations[name] = r
            return r
        }
    }
    
    public func beginTransaction() {
        precondition(!inTransaction, "We don't do nested transactions (yet?)")
        
        for (_, r) in relations {
            self.beginTransactionForRelation(r)
        }
        
        inTransaction = true
    }
    
    func beginTransactionForRelation(r: TransactionalRelation) {
        r.transactionRelation = r.underlyingRelation.deriveChangeLoggingRelation()
    }
    
    public func endTransaction() -> Result<Void, RelationError> {
        precondition(inTransaction, "Can't end transaction when we're not in one")
        
        var changes: [(TransactionalRelation, RelationChange)] = []
        for (_, r) in relations {
            let result = endTransactionForRelation(r)
            switch result {
            case .Ok(let change):
                changes.append((r, change))
            case .Err(let err):
                return .Err(err)
            }
        }
        
        for (r, _) in changes {
            r.notifyObserversTransactionBegan()
        }
        
        for (r, change) in changes {
            r.notifyChangeObservers(change)
        }
        
        for (r, _) in changes {
            r.notifyObserversTransactionEnded()
        }
        
        inTransaction = false
        
        return .Ok()
    }
    
    func endTransactionForRelation(r: TransactionalRelation) -> Result<RelationChange, RelationError> {
        // In computing the change log, we're assuming that target hasn't been changed.
        // Right now we don't support directly changing the database during a transaction.
        // If we ever do, it would involve retrying the transaction so this should still hold.
        let underlying = r.underlyingRelation
        let transaction = r.transactionRelation!
        
        r.transactionRelation = nil
        return underlying.restoreFromChangeLoggingRelation(transaction)
    }
    
    public func takeSnapshot() -> ChangeLoggingDatabaseSnapshot {
        return changeLoggingDatabase.takeSnapshot()
    }
    
    public func restoreSnapshot(snapshot: ChangeLoggingDatabaseSnapshot) {
        precondition(!inTransaction, "Can't restore a snapshot while in a transaction")
        changeLoggingDatabase.restoreSnapshot(snapshot)
    }
    
    public func transaction(transactionFunction: Void -> Void) {
        beginTransaction()
        transactionFunction()
        endTransaction()
    }
    
    public func transactionWithSnapshots(transactionFunction: Void -> Void) -> (before: ChangeLoggingDatabaseSnapshot, after: ChangeLoggingDatabaseSnapshot) {
        let before = takeSnapshot()
        transaction(transactionFunction)
        let after = takeSnapshot()
        return (before, after)
    }
}

extension TransactionalDatabase {
    public class TransactionalRelation: MutableRelation, RelationDefaultChangeObserverImplementation {
        var underlyingRelation: ChangeLoggingRelation<SQLiteTableRelation>
        var transactionRelation: ChangeLoggingRelation<SQLiteTableRelation>?
        
        public var changeObserverData = RelationDefaultChangeObserverImplementationData()
        
        init(underlyingRelation: ChangeLoggingRelation<SQLiteTableRelation>) {
            self.underlyingRelation = underlyingRelation
            underlyingRelation.addWeakChangeObserver(self, method: self.dynamicType.observeUnderlyingChange)
        }
        
        public var scheme: Scheme {
            return underlyingRelation.scheme
        }
        
        public func rawGenerateRows() -> AnyGenerator<Result<Row, RelationError>> {
            let data = LogRelationIterationBegin(self)
            return LogRelationIterationReturn(data, (transactionRelation ?? underlyingRelation).rawGenerateRows())
        }
        
        public func contains(row: Row) -> Result<Bool, RelationError> {
            return (transactionRelation ?? underlyingRelation).contains(row)
        }
        
        public func add(row: Row) -> Result<Int64, RelationError> {
            return (transactionRelation ?? underlyingRelation).add(row)
        }
        
        public func delete(query: SelectExpression) -> Result<Void, RelationError> {
            return (transactionRelation ?? underlyingRelation).delete(query)
        }
        
        public func update(query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
            return (transactionRelation ?? underlyingRelation).update(query, newValues: newValues)
        }
        
        func observeUnderlyingChange(change: RelationChange) {
            self.notifyChangeObservers(change)
        }
    }
}

