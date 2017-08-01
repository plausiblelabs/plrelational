//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

/// :nodoc:
public protocol UnaryOperator {
    func evaluate(_ value: RelationValue) -> RelationValue
}

/// :nodoc:
public struct NotOperator: UnaryOperator {
    public init() {}
    
    public func evaluate(_ value: RelationValue) -> RelationValue {
        return .integer(value.boolValue ? 0 : 1)
    }
}

/// :nodoc:
extension NotOperator: CustomStringConvertible {
    public var description: String {
        return "!"
    }
}
