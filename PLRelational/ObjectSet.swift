//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

/// :nodoc: Implementation detail (will be made non-public eventually)
/// Like a Set, but based on object identity rather than value equality.
public struct ObjectSet<T: AnyObject>: Sequence {
    fileprivate var set: Set<ObjectSetWrapper<T>>
    
    public init(_ elements: [T]) {
        set = Set(elements.map(ObjectSetWrapper.init))
    }
    
    public func makeIterator() -> AnyIterator<T> {
        let gen = set.lazy.map({ $0.object }).makeIterator()
        return AnyIterator(gen)
    }
    
    public var isEmpty: Bool {
        return set.isEmpty
    }
    
    public mutating func insert(_ obj: T) {
        set.insert(ObjectSetWrapper(object: obj))
    }
    
    public mutating func remove(_ obj: T) {
        set.remove(ObjectSetWrapper(object: obj))
    }
    
    public func contains(_ obj: T) -> Bool {
        return set.contains(ObjectSetWrapper(object: obj))
    }
    
    public var any: T? {
        return set.first?.object
    }
    
    public mutating func removeFirst() -> T {
        return set.removeFirst().object
    }
}

struct ObjectSetWrapper<T: AnyObject>: Hashable {
    var object: T
    
    var hashValue: Int {
        return ObjectIdentifier(object).hashValue
    }
}

func ==<T: AnyObject>(a: ObjectSetWrapper<T>, b: ObjectSetWrapper<T>) -> Bool {
    return a.object === b.object
}

/// :nodoc: Implementation detail (will be made non-public eventually)
extension ObjectSet: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: T...) {
        self.init(elements)
    }
}
