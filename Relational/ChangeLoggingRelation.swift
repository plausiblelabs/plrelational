
public enum ChangeLoggingRelationChange {
    case Add(Row)
    case Delete(SelectExpression)
    case Update(SelectExpression, Row)
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
        log.append(.Add(row))
        notifyChangeObservers(RelationChange(added: ConcreteRelation(row), removed: nil))
    }
    
    public func delete(query: SelectExpression) {
        let toDelete = computeFinalRelation().select(query)
        log.append(.Delete(query))
        notifyChangeObservers(RelationChange(added: nil, removed: toDelete))
    }
    
    public func update(query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        let currentState = computeFinalRelation()
        let toUpdate = currentState.select(query)
        let afterUpdate = toUpdate.withUpdate(newValues)
        
        log.append(.Update(query, newValues))
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
    
    private func computeFinalRelation() -> Relation {
        var currentRelation: Relation = underlyingRelation
        
        for change in log {
            switch change {
            case .Add(let row):
                let toAdd = ConcreteRelation(row)
                currentRelation = currentRelation.union(toAdd)
            case .Delete(let query):
                currentRelation = currentRelation.select(*!query)
            case .Update(let query, let newValues):
                currentRelation = currentRelation.withUpdate(query, newValues: newValues)
            }
        }
        
        return currentRelation
    }
}

extension ChangeLoggingRelation where UnderlyingRelation: SQLiteTableRelation {
    public func save() -> Result<Void, RelationError> {
        // TODO: transactions!
        for change in log {
            let err: RelationError?
            switch change {
            case .Add(let row):
                err = underlyingRelation.add(row).err
            case .Delete(let terms):
                err = underlyingRelation.delete(terms).err
            case .Update(let terms, let newValues):
                // Note: without the `as SQLiteTableRelation`, this generates an error due to ambiguity for some reason.
                err = (underlyingRelation as SQLiteTableRelation).update(terms, newValues: newValues).err
            }
            if let err = err {
                return .Err(err)
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
