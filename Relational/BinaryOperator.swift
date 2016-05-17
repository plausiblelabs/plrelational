
public protocol BinaryOperator {
    func evaluate(a: RelationValue, _ b: RelationValue) -> RelationValue
}

public struct EqualityComparator: BinaryOperator {
    public init() {}
    
    public func evaluate(a: RelationValue, _ b: RelationValue) -> RelationValue {
        return .boolValue(a == b)
    }
}

public struct LTComparator: BinaryOperator {
    public init() {}
    
    public func evaluate(a: RelationValue, _ b: RelationValue) -> RelationValue {
        return .boolValue(a < b)
    }
}

public struct AndComparator: BinaryOperator {
    public init() {}
    
    public func evaluate(a: RelationValue, _ b: RelationValue) -> RelationValue {
        return .boolValue(a.boolValue && b.boolValue)
    }
}

public struct AnyComparator: BinaryOperator {
    var compare: (RelationValue, RelationValue) -> Bool
    
    public init(_ compare: (RelationValue, RelationValue) -> Bool) {
        self.compare = compare
    }
    
    public func evaluate(a: RelationValue, _ b: RelationValue) -> RelationValue {
        return .boolValue(compare(a, b))
    }
}

extension EqualityComparator: CustomStringConvertible {
    public var description: String {
        return "="
    }
}

extension LTComparator: CustomStringConvertible {
    public var description: String {
        return "<"
    }
}

extension AndComparator: CustomStringConvertible {
    public var description: String {
        return "AND"
    }
}
