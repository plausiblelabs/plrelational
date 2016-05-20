
public enum ChangeLoggingRelationChange {
    case Union(Relation)
    case Select(SelectExpression)
    case Update(SelectExpression, Row)
}

public struct ChangeLoggingRelationSnapshot {
    var savedLog: [ChangeLoggingRelationChange]
}

public class ChangeLoggingRelation<BaseRelation: Relation> {
    let baseRelation: BaseRelation
    
    var log: [ChangeLoggingRelationChange] = []
    
    public var changeObserverData = RelationDefaultChangeObserverImplementationData()
    
    var currentChange: (added: ConcreteRelation, removed: ConcreteRelation)
    
    public init(baseRelation: BaseRelation) {
        self.baseRelation = baseRelation
        currentChange = (ConcreteRelation(scheme: baseRelation.scheme), ConcreteRelation(scheme: baseRelation.scheme))
    }
    
    public func update(query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        log.append(.Update(query, newValues))
        let result = applyLogToCurrentRelationAndGetChanges(log.suffix(1))
        return result.map({
            notifyChangeObservers($0)
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
        let relation = ConcreteRelation(row)
        log.append(.Union(relation))
        let result = self.applyLogToCurrentRelationAndGetChanges(log.suffix(1))
        return result.map({
            notifyChangeObservers($0)
            return 0
        })
    }
    
    public func delete(query: SelectExpression) -> Result<Void, RelationError> {
        log.append(.Select(*!query))
        let result = self.applyLogToCurrentRelationAndGetChanges(log.suffix(1))
        return result.map({
            notifyChangeObservers($0)
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
    public func save() -> Result<Void, RelationError> {
        // TODO: transactions!
        let change = ChangeLoggingRelation.computeChangeFromLog(self.log, baseRelation: self.baseRelation)
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
        if snapshot.savedLog.count > self.log.count {
            // The snapshot is ahead. Advance our state by the snapshot's log.
            let log = snapshot.savedLog.suffixFrom(self.log.count)
            self.log = snapshot.savedLog
            return applyLogToCurrentRelationAndGetChanges(log)
        } else {
            // The snapshot is behind. We don't (yet?) support reverse deltas, so just blow away
            // our entire state and recompute.
            let before = currentRelation()
            self.log = snapshot.savedLog
            self.currentChange = (ConcreteRelation(scheme: self.scheme), ConcreteRelation(scheme: self.scheme))
            return applyLogToCurrentRelation(self.log).map({
                let after = self.currentRelation()
                return RelationChange(added: after.difference(before), removed: before.difference(after))
            })
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
