//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//


/// An in-memory mutable Relation. Conceptually similar to ConcreteRelation, except that
/// this is a reference type rather than a value type, and so behaves more like we might
/// expect a "table" to. It's also observable, in case you need that sort of thing.
public class MemoryTableRelation: Relation, RelationDefaultChangeObserverImplementation {
    public let scheme: Scheme
    
    var values: Set<Row> = []
    
    public var changeObserverData = RelationDefaultChangeObserverImplementationData()
    
    public init(scheme: Scheme) {
        self.scheme = scheme
    }
    
    public var contentProvider: RelationContentProvider {
        return .Set({ self.values })
    }
    
    public func contains(row: Row) -> Result<Bool, RelationError> {
        return .Ok(values.contains(row))
    }
    
    public func update(query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        let toUpdate = values.filter({ query.valueWithRow($0).boolValue })
        values.subtractInPlace(toUpdate)
        
        let updated = toUpdate.map({ $0.rowWithUpdate(newValues) })
        values.unionInPlace(updated)
        
        return .Ok()
    }
    
    public func add(row: Row) {
        if !values.contains(row) {
            values.insert(row)
            notifyChangeObservers(RelationChange(added: ConcreteRelation(row), removed: nil), kind: .DirectChange)
        }
    }
    
    public func delete(query: SelectExpression) {
        let toDelete = Set(values.lazy.filter({ query.valueWithRow($0).boolValue }))
        values.subtractInPlace(toDelete)
        notifyChangeObservers(RelationChange(added: nil, removed: ConcreteRelation(scheme: scheme, values: toDelete)), kind: .DirectChange)
    }
    
    public func delete(row: Row) {
        if values.contains(row) {
            values.remove(row)
            notifyChangeObservers(RelationChange(added: nil, removed: ConcreteRelation(row)), kind: .DirectChange)
        }
    }
    
    public func copy() -> MemoryTableRelation {
        let copy = MemoryTableRelation(scheme: scheme)
        copy.values = values
        return copy
    }
}
