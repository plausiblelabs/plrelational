
public protocol ValueProvider {
    func valueForRow(row: Row) -> Value
}

public protocol Comparator {
    func matches(a: Value, _ b: Value) -> Bool
}

extension Attribute: ValueProvider {
    public func valueForRow(row: Row) -> Value {
        return row[self]
    }
}

extension String: ValueProvider {
    public func valueForRow(row: Row) -> Value {
        return self
    }
}

public struct EqualityComparator: Comparator {
    public init() {}
    
    public func matches(a: Value, _ b: Value) -> Bool {
        return a == b
    }
}

public struct LTComparator: Comparator {
    public init() {}
    
    public func matches(a: Value, _ b: Value) -> Bool {
        return a < b
    }
}

public struct AnyComparator: Comparator {
    var compare: (Value, Value) -> Bool
    
    public init(_ compare: (Value, Value) -> Bool) {
        self.compare = compare
    }
    
    public func matches(a: Value, _ b: Value) -> Bool {
        return compare(a, b)
    }
}
