//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

/// A `Relation` whose scheme is a single typed attribute.
public struct TypedRelation<Attr: TypedAttribute>: Relation {
    /// The underlying untyped `Relation` which provides our data.
    var wrapped: Relation
    
    public var scheme: Scheme {
        return wrapped.scheme
    }
    
    public var contentProvider: RelationContentProvider {
        return .underlying(wrapped)
    }
    
    public var debugName: String?
    
    public func contains(_ row: Row) -> Result<Bool, RelationError> {
        return wrapped.contains(row)
    }
    
    public mutating func update(_ query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        return wrapped.update(query, newValues: newValues)
    }
    
    public func addChangeObserver(_ observer: RelationObserver, kinds: [RelationObservationKind]) -> (() -> Void) {
        return wrapped.addChangeObserver(observer, kinds: kinds)
    }
}

public extension TypedRelation {
    /// Do an async fetch of all values in this `Relation`, providing them in chunks as they become available.
    /// Equivalent to `Relation.asyncBulkRows` but with a conversion step to this `TypeRelation`'s attribute
    /// value type.
    func asyncBulkValues(_ callback: DispatchContextWrapped<(Result<Set<Attr.Value>, RelationError>) -> Void>) {
        var didError = false
        asyncBulkRows(callback.context.wrap({ result in
            if didError { return }
            
            let convertedResult = result.then(Attr.makeValues)
            callback.wrapped(convertedResult)
            didError = convertedResult.err != nil
        }))
    }
    
    /// Do an async fetch of all values in this `Relation`, providing them in chunks as they become available.
    /// Equivalent to `Relation.asyncBulkRows` but with a conversion step to this `TypeRelation`'s attribute
    /// value type.
    func asyncBulkValues(_ callback: @escaping (Result<Set<Attr.Value>, RelationError>) -> Void) {
        asyncBulkValues(AsyncManager.currentInstance.runloopDispatchContext().wrap(callback))
    }
    
    /// Do an async fetch of all values in this `Relation`, providing them all at once in a set. Equivalent to
    /// `Relation.asyncBulkRows` but with a conversion step to this `TypeRelation`'s attribute value type.
    func asyncAllValues(_ callback: DispatchContextWrapped<(Result<Set<Attr.Value>, RelationError>) -> Void>) {
        asyncAllRows(callback.context.wrap({ result in
            let convertedResult = result.then(Attr.makeValues)
            callback.wrapped(convertedResult)
        }))
    }
    
    /// Do an async fetch of all values in this `Relation`, providing them all at once in a set. Equivalent to
    /// `Relation.asyncBulkRows` but with a conversion step to this `TypeRelation`'s attribute value type.
    func asyncAllValues(_ callback: @escaping (Result<Set<Attr.Value>, RelationError>) -> Void) {
        asyncAllValues(AsyncManager.currentInstance.runloopDispatchContext().wrap(callback))
    }
}

public extension Relation {
    /// Project this `Relation` onto a scheme of a single typed attribute, and return the projection as a
    /// `TypedRelation` for that attribute.
    func project<Attr: TypedAttribute>(_ typedAttribute: Attr.Type = Attr.self) -> TypedRelation<Attr> {
        return TypedRelation(wrapped: self.project(Attr.attribute), debugName: nil)
    }
}

public extension TypedAttribute {
    /// The specialized `TypedRelation` type you get from applying this typed attribute.
    public typealias Relation = TypedRelation<Self>
}

private extension TypedAttribute {
    /// Transform a set of rows into a set of attribute values, or an error if any of the conversions fail.
    static func makeValues(_ rows: Set<Row>) -> Result<Set<Self.Value>, RelationError> {
        var set = Set<Self.Value>(minimumCapacity: rows.count)
        for row in rows {
            switch Self.Value.make(from: row[Self.attribute]) {
            case .Ok(let value): set.insert(value)
            case .Err(let err): return .Err(err)
            }
        }
        return .Ok(set)
    }
}

