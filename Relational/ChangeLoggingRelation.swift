
/// Temporary typealias while we figure out the types. Should these be identical? Does the this code need more?
typealias ChangeLoggingRelationChange = RelationChange

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
        notifyChangeObservers([.Add(row)])
    }
    
    public func delete(query: SelectExpression) {
        log.append(.Delete(query))
        notifyChangeObservers([.Delete(query)])
    }
    
    public func update(query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        log.append(.Update(query, newValues))
        notifyChangeObservers([.Update(query, newValues)])
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
                // Figure out which attributes are being altered.
                let newValuesScheme = Scheme(attributes: Set(newValues.values.keys))
                
                // And which attributes are not being altered.
                let untouchedAttributesScheme = Scheme(attributes: self.scheme.attributes.subtract(newValuesScheme.attributes))
                
                // Pick out the rows which will be updated.
                let toUpdate = currentRelation.select(query)
                
                // Compute the update. We project away the updated attributes, then join in the new values.
                // The result is equivalent to updating the values.
                let withoutNewValueAttributes = toUpdate.project(untouchedAttributesScheme)
                let updatedValues = withoutNewValueAttributes.join(ConcreteRelation(newValues))
                
                // Pick out the rows not selected for the update.
                let nonUpdated = currentRelation.select(*!query)
                
                // The result is the union of the updated values and the rows not selected.
                currentRelation = nonUpdated.union(updatedValues)
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
            notifyChangeObservers([])
        }
    }
    
    public func restoreEmptySnapshot(notifyObservers notifyObservers: Bool = true) {
        self.log = []
        if notifyObservers {
            // XXX TODO: we need to provide the actual changes here!
            notifyChangeObservers([])
        }
    }
}
