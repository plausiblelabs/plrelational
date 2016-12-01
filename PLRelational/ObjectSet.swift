//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

/// Like a Set, but based on object identity rather than value equality.
struct ObjectSet<T: AnyObject>: Sequence {
    fileprivate var set: Set<ObjectSetWrapper<T>>
    
    init(_ elements: [T]) {
        set = Set(elements.map(ObjectSetWrapper.init))
    }
    
    func makeIterator() -> AnyIterator<T> {
        let gen = set.lazy.map({ $0.object }).makeIterator()
        return AnyIterator(gen)
    }
    
    var isEmpty: Bool {
        return set.isEmpty
    }
    
    mutating func insert(_ obj: T) {
        set.insert(ObjectSetWrapper(object: obj))
    }
    
    mutating func remove(_ obj: T) {
        set.remove(ObjectSetWrapper(object: obj))
    }
    
    func contains(_ obj: T) -> Bool {
        return set.contains(ObjectSetWrapper(object: obj))
    }
    
    var any: T? {
        return set.first?.object
    }
    
    mutating func removeFirst() -> T {
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

extension ObjectSet: ExpressibleByArrayLiteral {
    init(arrayLiteral elements: T...) {
        self.init(elements)
    }
}
