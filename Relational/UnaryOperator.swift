
public protocol UnaryOperator {
    func evaluate(value: RelationValue) -> RelationValue
}

public struct NotOperator: UnaryOperator {
    public init() {}
    
    public func evaluate(value: RelationValue) -> RelationValue {
        return .Integer(value.boolValue ? 0 : 1)
    }
}

extension NotOperator: CustomStringConvertible {
    public var description: String {
        return "!"
    }
}