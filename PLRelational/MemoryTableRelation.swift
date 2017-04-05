//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//


/// An in-memory mutable Relation. Conceptually similar to ConcreteRelation, except that
/// this is a reference type rather than a value type, and so behaves more like we might
/// expect a "table" to. It's also observable, in case you need that sort of thing.
open class MemoryTableRelation: Relation, MutableRelation, RelationDefaultChangeObserverImplementation {
    open let scheme: Scheme
    
    public var values: Set<Row> = []
    
    open var changeObserverData = RelationDefaultChangeObserverImplementationData()
    
    public init(scheme: Scheme) {
        self.scheme = scheme
    }
    
    public static func copyRelation(_ other: Relation) -> Result<MemoryTableRelation, RelationError> {
        return mapOk(other.rows(), { $0 }).map({
            let r = MemoryTableRelation(scheme: other.scheme)
            r.values = Set($0)
            return r
        })
    }
    
    open var contentProvider: RelationContentProvider {
        return .set({ self.values }, approximateCount: Double(self.values.count))
    }
    
    open func contains(_ row: Row) -> Result<Bool, RelationError> {
        return .Ok(values.contains(row))
    }
    
    open func update(_ query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        let toUpdate = values.filter({ query.valueWithRow($0).boolValue })
        values.subtract(toUpdate)
        
        let updated = toUpdate.map({ $0.rowWithUpdate(newValues) })
        values.formUnion(updated)
        
        return .Ok()
    }
    
    open func add(_ row: Row) -> Result<Int64, RelationError> {
        if !values.contains(row) {
            values.insert(row)
            notifyChangeObservers(RelationChange(added: ConcreteRelation(row), removed: nil), kind: .directChange)
        }
        return .Ok(0)
    }
    
    open func delete(_ query: SelectExpression) -> Result<Void, RelationError> {
        let toDelete = Set(values.lazy.filter({ query.valueWithRow($0).boolValue }))
        values.fastSubtract(toDelete)
        notifyChangeObservers(RelationChange(added: nil, removed: ConcreteRelation(scheme: scheme, values: toDelete)), kind: .directChange)
        return .Ok()
    }
    
    open func delete(_ row: Row) {
        if values.contains(row) {
            values.remove(row)
            notifyChangeObservers(RelationChange(added: nil, removed: ConcreteRelation(row)), kind: .directChange)
        }
    }
    
    open func copy() -> MemoryTableRelation {
        let copy = MemoryTableRelation(scheme: scheme)
        copy.values = values
        return copy
    }
}

public func MakeRelation(_ attributes: [Attribute], _ rowValues: [RelationValue]...) -> MemoryTableRelation {
    let scheme = Scheme(attributes: Set(attributes))
    let rows = rowValues.map({ values -> Row in
        precondition(values.count == attributes.count)
        return Row(values: Dictionary(zip(attributes, values)))
    })
    let r = MemoryTableRelation(scheme: scheme)
    r.values = Set(rows)
    return r
}
