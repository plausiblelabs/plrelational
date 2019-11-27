//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
public protocol UnaryOperator {
    func evaluate(_ value: RelationValue) -> RelationValue
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
public struct NotOperator: UnaryOperator {
    public init() {}
    
    public func evaluate(_ value: RelationValue) -> RelationValue {
        return .integer(value.boolValue ? 0 : 1)
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
extension NotOperator: CustomStringConvertible {
    public var description: String {
        return "!"
    }
}
