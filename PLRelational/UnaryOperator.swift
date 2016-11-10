//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

public protocol UnaryOperator {
    func evaluate(_ value: RelationValue) -> RelationValue
}

public struct NotOperator: UnaryOperator {
    public init() {}
    
    public func evaluate(_ value: RelationValue) -> RelationValue {
        return .integer(value.boolValue ? 0 : 1)
    }
}

extension NotOperator: CustomStringConvertible {
    public var description: String {
        return "!"
    }
}