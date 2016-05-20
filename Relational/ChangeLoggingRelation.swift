
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
    
    var log: [ChangeLoggingRelationChange] = [] {
        didSet {
            self.current = nil
        }
    }
    
    public var changeObserverData = RelationDefaultChangeObserverImplementationData()
    
    var current: (added: ConcreteRelation, removed: ConcreteRelation)?
    
    public init(baseRelation: BaseRelation) {
        self.baseRelation = baseRelation
    }
    
    public func update(query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        return computeFinalRelation().map({ currentState in
            let removed = currentState.select(query)
            let added = removed.withUpdate(newValues)
            
            log.append(.Update(query, newValues))
            notifyChangeObservers(RelationChange(added: added, removed: removed))
        })
    }
}

extension ChangeLoggingRelation: MutableRelation, RelationDefaultChangeObserverImplementation {
    public var scheme: Scheme {
        return baseRelation.scheme
    }
    
    public func rows() -> AnyGenerator<Result<Row, RelationError>> {
        switch computeFinalRelation() {
        case .Ok(let relation):
            return relation.rows()
        case .Err(let err):
            return AnyGenerator(CollectionOfOne(Result.Err(err)).generate())
        }
    }
    
    public func contains(row: Row) -> Result<Bool, RelationError> {
        return computeFinalRelation().then({ $0.contains(row) })
    }
    
    public func add(row: Row) -> Result<Int64, RelationError> {
        let relation = ConcreteRelation(row)
        log.append(.Union(relation))
        notifyChangeObservers(RelationChange(added: relation, removed: nil))
        return .Ok(0)
    }
    
    public func delete(query: SelectExpression) -> Result<Void, RelationError> {
        return computeFinalRelation().map({ finalRelation in
            let toDelete = finalRelation.select(query)
            log.append(.Select(*!query))
            notifyChangeObservers(RelationChange(added: nil, removed: toDelete))
        })
    }
    
//    internal func
    
    internal func computeFinalRelation() -> Result<Relation, RelationError> {
        if let (added, removed) = self.current {
            return .Ok(baseRelation.difference(removed).union(added))
        }
        
        var addedRows = ConcreteRelation(scheme: scheme, values: [], defaultSort: nil)
        var removedRows = ConcreteRelation(scheme: scheme, values: [], defaultSort: nil)
        
        for change in log {
            switch change {
            case .Union(let relation):
                for row in relation.rows() {
                    switch row {
                    case .Ok(let row):
                        addedRows.add(row)
                        removedRows.delete(row)
                    case .Err(let err):
                        return .Err(err)
                    }
                }
            case .Select(let query):
                addedRows.delete(*!query)
                for row in baseRelation.select(*!query).rows() {
                    switch row {
                    case .Ok(let row):
                        removedRows.add(row)
                    case .Err(let err):
                        return .Err(err)
                    }
                }
            case .Update(let query, let newValues):
                addedRows.update(query, newValues: newValues)
                for toUpdate in baseRelation.select(query).difference(removedRows).rows() {
                    switch toUpdate {
                    case .Ok(let row):
                        addedRows.add(Row(values: row.values + newValues.values))
                        removedRows.add(row)
                    case .Err(let err):
                        return .Err(err)
                    }
                }
            }
        }
        
        current = (addedRows, removedRows)
        
        return .Ok(baseRelation.difference(removedRows).union(addedRows))
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
    
    public func restoreSnapshot(snapshot: ChangeLoggingRelationSnapshot) {
        let change = rawRestoreSnapshot(snapshot)
        notifyChangeObservers(change)
    }
    
    /// Restore a snapshot and compute the changes that this causes. Does not notify observers.
    func rawRestoreSnapshot(snapshot: ChangeLoggingRelationSnapshot) -> RelationChange {
        if snapshot.savedLog.count > self.log.count {
            let log = snapshot.savedLog.suffixFrom(self.log.count)
            // TODO: handle errors on all computeFinalRelation calls
            let change = self.dynamicType.computeChangeFromLog(log, baseRelation: self.computeFinalRelation().ok!)
            self.log = snapshot.savedLog
            return change
        } else {
            let log = self.log.suffixFrom(snapshot.savedLog.count)
            self.log = snapshot.savedLog
            let change = self.dynamicType.computeChangeFromLog(log, baseRelation: self.computeFinalRelation().ok!)
            let reversedChange = RelationChange(added: change.removed, removed: change.added)
            return reversedChange
        }
    }
}
