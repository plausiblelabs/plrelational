
enum ChangeLoggingRelationChange {
    case Union(Relation)
    case Select(SelectExpression)
    case Update(SelectExpression, Row)
}

struct ChangeLoggingRelationLogEntry {
    var forward: ChangeLoggingRelationChange
    var backward: [ChangeLoggingRelationChange]
}

public struct ChangeLoggingRelationSnapshot {
    var savedLog: [ChangeLoggingRelationLogEntry]
}

public class ChangeLoggingRelation<BaseRelation: Relation> {
    let baseRelation: BaseRelation
    
    var log: [ChangeLoggingRelationLogEntry] = []
    
    public var changeObserverData = RelationDefaultChangeObserverImplementationData()
    
    var currentChange: (added: ConcreteRelation, removed: ConcreteRelation)
    
    public init(baseRelation: BaseRelation) {
        self.baseRelation = baseRelation
        currentChange = (ConcreteRelation(scheme: baseRelation.scheme), ConcreteRelation(scheme: baseRelation.scheme))
    }
    
    public func update(query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        let change = ChangeLoggingRelationChange.Update(query, newValues)
        let result = applyLogToCurrentRelationAndGetChanges([change])
        return result.then({
            var reverse: [ChangeLoggingRelationChange] = []
            if let added = $0.added where added.isEmpty.ok != true {
                for row in added.rows() {
                    switch row {
                    case .Ok(let row):
                        reverse.append(.Select(*!SelectExpressionFromRow(row)))
                    case .Err(let err):
                        return .Err(err)
                    }
                }
            }
            if let removed = $0.removed where removed.isEmpty.ok != true {
                reverse.append(.Union(removed))
            }
            log.append(ChangeLoggingRelationLogEntry(forward: change, backward: reverse))
            
            notifyChangeObservers($0)
            
            return .Ok()
        })
    }
}

extension ChangeLoggingRelation: MutableRelation, RelationDefaultChangeObserverImplementation {
    public var scheme: Scheme {
        return baseRelation.scheme
    }
    
    public func rows() -> AnyGenerator<Result<Row, RelationError>> {
        return currentRelation().rows()
    }
    
    public func contains(row: Row) -> Result<Bool, RelationError> {
        return currentRelation().contains(row)
    }
    
    public func add(row: Row) -> Result<Int64, RelationError> {
        switch self.contains(row) {
        case .Ok(let contains):
            if !contains {
                let change = ChangeLoggingRelationChange.Union(ConcreteRelation(row))
                let logEntry = ChangeLoggingRelationLogEntry(
                    forward: change,
                    backward: [.Select(*!SelectExpressionFromRow(row))])
                log.append(logEntry)
                let result = self.applyLogToCurrentRelationAndGetChanges([change])
                return result.map({
                    notifyChangeObservers($0)
                    return 0
                })
            } else {
                return .Ok(0)
            }
        case .Err(let err):
            return .Err(err)
        }
    }
    
    public func delete(query: SelectExpression) -> Result<Void, RelationError> {
        return ConcreteRelation.copyRelation(self.select(query)).then({ rowsToDelete in
            let change = ChangeLoggingRelationChange.Select(*!query)
            let logEntry = ChangeLoggingRelationLogEntry(
                forward: change,
                backward: [.Union(rowsToDelete)])
            log.append(logEntry)
            let result = self.applyLogToCurrentRelationAndGetChanges([change])
            return result.map({
                notifyChangeObservers($0)
            })
        })
    }
    
    /// A Relation that describes the current state of the ChangeLoggingRelation.
    /// This is what rows() returns data from, but it won't reflect any future
    /// changes to the ChangeLoggingRelation.
    internal func currentRelation() -> Relation {
        return baseRelation.difference(currentChange.removed).union(currentChange.added)
    }
    
    private func applyLogToCurrentRelation<Log: SequenceType where Log.Generator.Element == ChangeLoggingRelationChange>(log: Log) -> Result<Void, RelationError> {
        for change in log {
            switch change {
            case .Union(let relation):
                for row in relation.rows() {
                    switch row {
                    case .Ok(let row):
                        currentChange.added.add(row)
                        currentChange.removed.delete(row)
                    case .Err(let err):
                        return .Err(err)
                    }
                }
            case .Select(let query):
                currentChange.added.delete(*!query)
                for row in baseRelation.select(*!query).rows() {
                    switch row {
                    case .Ok(let row):
                        currentChange.removed.add(row)
                    case .Err(let err):
                        return .Err(err)
                    }
                }
            case .Update(let query, let newValues):
                currentChange.added.update(query, newValues: newValues)
                for toUpdate in baseRelation.select(query).difference(currentChange.removed).rows() {
                    switch toUpdate {
                    case .Ok(let row):
                        currentChange.added.add(Row(values: row.values + newValues.values))
                        currentChange.removed.add(row)
                    case .Err(let err):
                        return .Err(err)
                    }
                }
            }
        }
        return .Ok()
    }
    
    private func applyLogToCurrentRelationAndGetChanges<Log: SequenceType where Log.Generator.Element == ChangeLoggingRelationChange>(log: Log) -> Result<RelationChange, RelationError> {
        let before = currentRelation()
        let result = applyLogToCurrentRelation(log)
        return result.map({
            let after = self.currentRelation()
            return RelationChange(added: after.difference(before), removed: before.difference(after))
        })
    }
    
    static func computeChangeFromLog<Log: SequenceType where Log.Generator.Element == ChangeLoggingRelationChange>(log: Log, baseRelation: Relation) -> RelationChange {
        var currentAdd: Relation = ConcreteRelation(scheme: baseRelation.scheme)
        var currentRemove: Relation = ConcreteRelation(scheme: baseRelation.scheme)
        
        for change in log {
            switch change {
            case .Union(let relation):
                currentAdd = currentAdd.union(relation.difference(currentRemove))
                currentRemove = currentRemove.difference(relation)
            case .Select(let query):
                currentAdd = currentAdd.select(query)
                currentRemove = currentRemove.union(baseRelation.select(*!query))
            case .Update(let query, let newValues):
                currentAdd = currentAdd.withUpdate(query, newValues: newValues)
                currentAdd = currentAdd.union(baseRelation.select(query).difference(currentRemove).withUpdate(newValues))
                currentRemove = currentRemove.union(baseRelation.select(query))
            }
        }
        
        return RelationChange(added: currentAdd, removed: currentRemove)
    }
}

extension ChangeLoggingRelation where BaseRelation: SQLiteTableRelation {
    /// Save changes into the underlying database. Note that this does *not* use a transaction.
    /// Since we're likely to be saving multiple tables at once, the transaction takes place
    /// in that code to ensure everything is done together.
    public func save() -> Result<Void, RelationError> {
        let change = ChangeLoggingRelation.computeChangeFromLog(self.log.lazy.map({ $0.forward }), baseRelation: self.baseRelation)
        if let removed = change.removed {
            for row in removed.rows() {
                switch row {
                case .Ok(let row):
                    if let err = baseRelation.delete(SelectExpressionFromRow(row)).err {
                        return .Err(err)
                    }
                case .Err(let err):
                    return .Err(err)
                }
            }
        }
        
        if let added = change.added {
            for row in added.rows() {
                switch row {
                case .Ok(let row):
                    if let err = baseRelation.add(row).err {
                        return .Err(err)
                    }
                case .Err(let err):
                    return .Err(err)
                }
                
            }
        }
        
        return .Ok()
    }
}

extension ChangeLoggingRelation {
    public func takeSnapshot() -> ChangeLoggingRelationSnapshot {
        return ChangeLoggingRelationSnapshot(savedLog: self.log)
    }
    
    public func restoreSnapshot(snapshot: ChangeLoggingRelationSnapshot) -> Result<Void, RelationError> {
        let change = rawRestoreSnapshot(snapshot)
        return change.map({
            notifyChangeObservers($0)
        })
    }
    
    /// Restore a snapshot and compute the changes that this causes. Does not notify observers.
    func rawRestoreSnapshot(snapshot: ChangeLoggingRelationSnapshot) -> Result<RelationChange, RelationError> {
        // Note: right now we assume that the snapshot's log is a prefix of ours, or vice versa. We don't support
        // tree snapshots (yet?).
        if snapshot.savedLog.count > self.log.count {
            // The snapshot is ahead. Advance our state by the snapshot's log.
            let log = snapshot.savedLog.suffixFrom(self.log.count)
            self.log = snapshot.savedLog
            return applyLogToCurrentRelationAndGetChanges(log.lazy.map({ $0.forward }))
        } else {
            // The snapshot is behind. Reverse our state by our backwards log.
            let log = self.log.suffixFrom(snapshot.savedLog.count)
            self.log = snapshot.savedLog
            let backwardsLog = log.flatMap({ $0.backward }).reverse()
            return applyLogToCurrentRelationAndGetChanges(backwardsLog)
        }
    }
    
    func deriveChangeLoggingRelation() -> ChangeLoggingRelation<BaseRelation> {
        let relation = ChangeLoggingRelation(baseRelation: self.baseRelation)
        relation.log = self.log
        relation.currentChange = self.currentChange
        return relation
    }
    
    func restoreFromChangeLoggingRelation(relation: ChangeLoggingRelation<BaseRelation>) -> Result<RelationChange, RelationError> {
        // This snapshot thing is kind of elegant and ugly at the same time. It gets the job done
        // of applying the new state and retrieving the changes, anyway.
        let pretendSnapshot = relation.takeSnapshot()
        return rawRestoreSnapshot(pretendSnapshot)
    }
}
