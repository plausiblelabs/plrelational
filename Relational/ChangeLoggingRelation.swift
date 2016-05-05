
public class ChangeLoggingRelation {
    enum Change {
        case Add(Row)
        case Delete([ComparisonTerm])
    }
    
    private let underlyingRelation: Relation
    
    private var log: [Change] = []
    
    private var changeObservers: [UInt64: Void -> Void] = [:]
    private var changeObserverNextID: UInt64 = 0
    
    public init(underlyingRelation: Relation) {
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
        
    }
}

extension ChangeLoggingRelation: Relation {
    public var scheme: Scheme {
        return underlyingRelation.scheme
    }
    
    public func rows() -> AnyGenerator<Result<Row, RelationError>> {
        var myRows = ConcreteRelation(scheme: scheme, values: [], defaultSort: nil)
        var deletions: [[ComparisonTerm]] = []
        for change in log {
            switch change {
            case .Add(let row):
                myRows.add(row)
            case .Delete(let terms):
                myRows.delete(terms)
                deletions.append(terms)
            }
        }
        
        let underlyingRows = underlyingRelation.rows()
        let filteredUnderlyingRows = underlyingRows.lazy.filter({
            if let row = $0.ok {
                for deletion in deletions {
                    if ComparisonTerm.terms(deletion, matchRow: row) {
                        return false
                    }
                }
            }
            return true
        })
        
        let allRows = myRows.rows().concat(filteredUnderlyingRows.generate())
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
