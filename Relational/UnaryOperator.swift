
public protocol UnaryOperator {
    func transform(value: RelationValue) -> RelationValue
}

public struct NotOperator: UnaryOperator {
    public init() {}
    
    public func transform(value: RelationValue) -> RelationValue {
        return .Integer(value.boolValue ? 0 : 1)
    }
}
