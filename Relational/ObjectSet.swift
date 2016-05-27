
/// Like a Set, but based on object identity rather than value equality.
struct ObjectSet<T: AnyObject>: SequenceType {
    private var set: Set<ObjectSetWrapper<T>>
    
    init(_ elements: [T]) {
        set = Set(elements.map(ObjectSetWrapper.init))
    }
    
    func generate() -> AnyGenerator<T> {
        let gen = set.lazy.map({ $0.object }).generate()
        return AnyGenerator(gen)
    }
    
    mutating func insert(obj: T) {
        set.insert(ObjectSetWrapper(object: obj))
    }
    
    func contains(obj: T) -> Bool {
        return set.contains(ObjectSetWrapper(object: obj))
    }
    
    var any: T? {
        return set.first?.object
    }
}

private struct ObjectSetWrapper<T: AnyObject>: Hashable {
    var object: T
    
    private var hashValue: Int {
        return ObjectIdentifier(object).hashValue
    }
}

private func ==<T: AnyObject>(a: ObjectSetWrapper<T>, b: ObjectSetWrapper<T>) -> Bool {
    return a.object === b.object
}

extension ObjectSet: ArrayLiteralConvertible {
    init(arrayLiteral elements: T...) {
        self.init(elements)
    }
}
