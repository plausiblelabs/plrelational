//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

public struct TypedRelation<Attr: TypedAttribute>: Relation {
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
    func asyncBulkValues(_ callback: DispatchContextWrapped<(Result<Set<Attr.Value>, RelationError>) -> Void>) {
        var didError = false
        asyncBulkRows(callback.context.wrap({ result in
            if didError { return }
            
            let convertedResult = result.then(Attr.makeValues)
            callback.wrapped(convertedResult)
            didError = convertedResult.err != nil
        }))
    }
    
    func asyncBulkValues(_ callback: @escaping (Result<Set<Attr.Value>, RelationError>) -> Void) {
        asyncBulkValues(AsyncManager.currentInstance.runloopDispatchContext().wrap(callback))
    }
    
    func asyncAllValues(_ callback: DispatchContextWrapped<(Result<Set<Attr.Value>, RelationError>) -> Void>) {
        asyncAllRows(callback.context.wrap({ result in
            let convertedResult = result.then(Attr.makeValues)
            callback.wrapped(convertedResult)
        }))
    }
    
    func asyncAllValues(_ callback: @escaping (Result<Set<Attr.Value>, RelationError>) -> Void) {
        asyncAllValues(AsyncManager.currentInstance.runloopDispatchContext().wrap(callback))
    }
}

public extension Relation {
    func project<Attr: TypedAttribute>() -> TypedRelation<Attr> {
        return TypedRelation(wrapped: self.project(Attr.name), debugName: nil)
    }
}

public extension TypedAttribute {
    public typealias Relation = TypedRelation<Self>
}

private extension TypedAttribute {
    static func makeValues(_ rows: Set<Row>) -> Result<Set<Self.Value>, RelationError> {
        var set = Set<Self.Value>(minimumCapacity: rows.count)
        for row in rows {
            switch Self.Value.make(from: row[Self.name]) {
            case .Ok(let value): set.insert(value)
            case .Err(let err): return .Err(err)
            }
        }
        return .Ok(set)
    }
}

