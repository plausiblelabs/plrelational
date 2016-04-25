
public protocol ValueProvider {
    func valueForRow(row: Row) -> RelationValue
}

public protocol Comparator {
    func matches(a: RelationValue, _ b: RelationValue) -> Bool
}

extension RelationValue: ValueProvider {
    public func valueForRow(row: Row) -> RelationValue {
        return self
    }
}

extension Attribute: ValueProvider {
    public func valueForRow(row: Row) -> RelationValue {
        return row[self]
    }
}

extension String: ValueProvider {
    public func valueForRow(row: Row) -> RelationValue {
        return RelationValue(self)
    }
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

public struct AnyComparator: Comparator {
    var compare: (RelationValue, RelationValue) -> Bool
    
    public init(_ compare: (RelationValue, RelationValue) -> Bool) {
        self.compare = compare
    }
    
    public func matches(a: RelationValue, _ b: RelationValue) -> Bool {
        return compare(a, b)
    }
}
