
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
        var myRows = ConcreteRelation(scheme: scheme, values: [], defaultSort: nil)
        for change in log {
            switch change {
            case .Add(let row):
                myRows.add(row)
            case .Delete(let terms):
                myRows.delete(terms)
            case .Update(let terms, let newValues):
                myRows.update(terms, newValues: newValues)
            }
        }
        
        let underlyingRows = underlyingRelation.rows()
        let alteredUnderlyingRows = underlyingRows.lazy.flatMap({ (row: Result<Row, RelationError>) -> Result<Row, RelationError>? in
            if var row = row.ok {
                for change in self.log {
                    switch change {
                    case .Add:
                        break
                    case .Delete(let query):
                        if query.valueWithRow(row).boolValue {
                            return nil
                        }
                    case .Update(let query, let newValues):
                        if query.valueWithRow(row).boolValue {
                            for (attribute, value) in newValues.values {
                                row[attribute] = value
                            }
                        }
                    }
                }
                return .Ok(row)
            } else {
                return row
            }
        })
        
        let allRows = myRows.rows().concat(alteredUnderlyingRows.generate())
        return AnyGenerator(allRows)
    }
    
    public func contains(row: Row) -> Result<Bool, RelationError> {
        return underlyingRelation.contains(row)
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
