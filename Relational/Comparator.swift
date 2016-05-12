
public protocol Comparator {
    func matches(a: RelationValue, _ b: RelationValue) -> Bool
}

public struct EqualityComparator: Comparator {
    public init() {}
    
    public func matches(a: RelationValue, _ b: RelationValue) -> Bool {
        return a == b
    }
}

public struct LTComparator: Comparator {
    public init() {}
    
    public func matches(a: RelationValue, _ b: RelationValue) -> Bool {
        return a < b
    }
}

public struct AndComparator: Comparator {
    public init() {}
    
    public func matches(a: RelationValue, _ b: RelationValue) -> Bool {
        return a.boolValue && b.boolValue
    }
}

public struct AnyComparator: Comparator {
    var compare: (RelationValue, RelationValue) -> Bool
    
    public init(_ compare: (RelationValue, RelationValue) -> Bool) {
        self.compare = compare
    }
    
    public func matches(a: RelationValue, _ b: RelationValue) -> Bool {
        return compare(a, b)
    }
}
