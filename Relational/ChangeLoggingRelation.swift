
enum ChangeLoggingRelationChange {
    case Add(Row)
    case Delete([ComparisonTerm])
    case Update([ComparisonTerm], Row)
}

public class ChangeLoggingRelation<UnderlyingRelation: Relation> {
    private let underlyingRelation: UnderlyingRelation
    
    private var log: [ChangeLoggingRelationChange] = []
    
    private var changeObservers: [UInt64: Void -> Void] = [:]
    private var changeObserverNextID: UInt64 = 0
    
    public init(underlyingRelation: UnderlyingRelation) {
        self.underlyingRelation = underlyingRelation
    }
    
    public func add(row: Row) {
        log.append(.Add(row))
        notifyChangeObservers()
    }
    
    public func delete(searchTerms: [ComparisonTerm]) {
        log.append(.Delete(searchTerms))
        notifyChangeObservers()
    }
    
    public func update(searchTerms: [ComparisonTerm], newValues: Row) {
        log.append(.Update(searchTerms, newValues))
        notifyChangeObservers()
    }
}

extension ChangeLoggingRelation: Relation {
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
                myRows.update(terms, to: newValues)
            }
        }
        
        let underlyingRows = underlyingRelation.rows()
        let alteredUnderlyingRows = underlyingRows.lazy.flatMap({ (row: Result<Row, RelationError>) -> Result<Row, RelationError>? in
            if var row = row.ok {
                for change in self.log {
                    switch change {
                    case .Add:
                        break
                    case .Delete(let terms):
                        if ComparisonTerm.terms(terms, matchRow: row) {
                            return nil
                        }
                    case .Update(let terms, let newValues):
                        if ComparisonTerm.terms(terms, matchRow: row) {
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
    
    public func addChangeObserver(f: Void -> Void) -> (Void -> Void) {
        let id = changeObserverNextID
        changeObserverNextID += 1
        
        changeObservers[id] = f
        
        return { self.changeObservers.removeValueForKey(id) }
    }
    
    private func notifyChangeObservers() {
        for (_, f) in changeObservers {
            f()
        }
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
                err = underlyingRelation.update(terms, newValues: newValues).err
            }
            if let err = err {
                return .Err(err)
            }
        }
        return .Ok()
    }
}
