
public enum ChangeLoggingRelationChange {
    case Union(Relation)
    case Select(SelectExpression)
}

public struct ChangeLoggingRelationSnapshot {
    var savedLog: [ChangeLoggingRelationChange]
}

public class ChangeLoggingRelation<UnderlyingRelation: Relation> {
    let underlyingRelation: UnderlyingRelation
    
    var log: [ChangeLoggingRelationChange] = []
    
    public var changeObserverData = RelationDefaultChangeObserverImplementationData()
    
    public init(underlyingRelation: UnderlyingRelation) {
        self.underlyingRelation = underlyingRelation
    }
    
    public func add(row: Row) {
        let relation = ConcreteRelation(row)
        log.append(.Union(relation))
        notifyChangeObservers(RelationChange(added: relation, removed: nil))
    }
    
    public func delete(query: SelectExpression) {
        let toDelete = computeFinalRelation().select(query)
        log.append(.Select(*!query))
        notifyChangeObservers(RelationChange(added: nil, removed: toDelete))
    }
    
    public func update(query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        let currentState = computeFinalRelation()
        let toUpdate = currentState.select(query)
        let afterUpdate = toUpdate.withUpdate(newValues)
        
        log.append(.Select(*!query))
        log.append(.Union(afterUpdate))
        notifyChangeObservers(RelationChange(added: afterUpdate, removed: toUpdate))
        return .Ok()
    }
}

extension ChangeLoggingRelation: Relation, RelationDefaultChangeObserverImplementation {
    public var scheme: Scheme {
        return underlyingRelation.scheme
    }
    
    public func rows() -> AnyGenerator<Result<Row, RelationError>> {
        return computeFinalRelation().rows()
    }
    
    public func contains(row: Row) -> Result<Bool, RelationError> {
        return computeFinalRelation().contains(row)
    }
    
    internal func computeFinalRelation() -> Relation {
        var currentRelation: Relation = underlyingRelation
        
        for change in log {
            switch change {
            case .Union(let relation):
                currentRelation = currentRelation.union(relation)
            case .Select(let query):
                currentRelation = currentRelation.select(query)
            }
        }
        
        return currentRelation
    }
    
    static func computeChangeFromLog<Log: SequenceType where Log.Generator.Element == ChangeLoggingRelationChange>(log: Log, underlyingRelation: Relation) -> RelationChange {
        var currentAdd: Relation = ConcreteRelation(scheme: underlyingRelation.scheme)
        var currentRemove: Relation = ConcreteRelation(scheme: underlyingRelation.scheme)
        
        for change in log {
            switch change {
            case .Union(let relation):
                currentAdd = currentAdd.union(relation.difference(currentRemove))
                currentRemove = currentRemove.difference(relation)
            case .Select(let query):
                currentAdd = currentAdd.select(query)
                currentRemove = currentRemove.union(underlyingRelation.select(*!query))
            }
        }
        
        return RelationChange(added: currentAdd, removed: currentRemove)
    }
}

extension ChangeLoggingRelation where UnderlyingRelation: SQLiteTableRelation {
    public func save() -> Result<Void, RelationError> {
        // TODO: transactions!
        let change = ChangeLoggingRelation.computeChangeFromLog(self.log, underlyingRelation: self.underlyingRelation)
        if let removed = change.removed {
            for row in removed.rows() {
                switch row {
                case .Ok(let row):
                    if let err = underlyingRelation.delete(SelectExpressionFromRow(row)).err {
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
                    if let err = underlyingRelation.add(row).err {
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
    
    public func restoreSnapshot(snapshot: ChangeLoggingRelationSnapshot, notifyObservers: Bool = true) {
        self.log = snapshot.savedLog
        if notifyObservers {
            // XXX TODO: we need to provide the actual changes here!
            notifyChangeObservers(RelationChange(added: nil, removed: nil))
        }
    }
    
    public func restoreEmptySnapshot(notifyObservers notifyObservers: Bool = true) {
        self.log = []
        if notifyObservers {
            // XXX TODO: we need to provide the actual changes here!
            notifyChangeObservers(RelationChange(added: nil, removed: nil))
        }
    }
}
