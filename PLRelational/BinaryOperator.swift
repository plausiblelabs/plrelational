//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import sqlite3

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
public protocol BinaryOperator {
    func evaluate(_ a: RelationValue, _ b: RelationValue) -> RelationValue
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
public struct EqualityComparator: BinaryOperator {
    public init() {}
    
    public func evaluate(_ a: RelationValue, _ b: RelationValue) -> RelationValue {
        return .boolValue(a == b)
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
public struct InequalityComparator: BinaryOperator {
    public init() {}
    
    public func evaluate(_ a: RelationValue, _ b: RelationValue) -> RelationValue {
        return .boolValue(a != b)
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
public struct LTComparator: BinaryOperator {
    public init() {}
    
    public func evaluate(_ a: RelationValue, _ b: RelationValue) -> RelationValue {
        return .boolValue(a < b)
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
public struct LEComparator: BinaryOperator {
    public init() {}
    
    public func evaluate(_ a: RelationValue, _ b: RelationValue) -> RelationValue {
        return .boolValue(a <= b)
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
public struct GTComparator: BinaryOperator {
    public init() {}
    
    public func evaluate(_ a: RelationValue, _ b: RelationValue) -> RelationValue {
        return .boolValue(a > b)
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
public struct GEComparator: BinaryOperator {
    public init() {}
    
    public func evaluate(_ a: RelationValue, _ b: RelationValue) -> RelationValue {
        return .boolValue(a >= b)
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
public struct AndComparator: BinaryOperator {
    public init() {}
    
    public func evaluate(_ a: RelationValue, _ b: RelationValue) -> RelationValue {
        return .boolValue(a.boolValue && b.boolValue)
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
public struct OrComparator: BinaryOperator {
    public init() {}
    
    public func evaluate(_ a: RelationValue, _ b: RelationValue) -> RelationValue {
        return .boolValue(a.boolValue || b.boolValue)
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
public struct GlobComparator: BinaryOperator {
    public init() {}
    
    public func evaluate(_ a: RelationValue, _ b: RelationValue) -> RelationValue {
        if let aString = a.get() as String?, let bString = b.get() as String? {
            return .boolValue(matches(aString, bString))
        } else {
            return .boolValue(false)
        }
    }
    
    fileprivate func matches(_ string: String, _ glob: String) -> Bool {
        return sqlite3_strglob(glob, string) == 0
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
public struct AnyComparator: BinaryOperator {
    var compare: (RelationValue, RelationValue) -> Bool
    
    public init(_ compare: @escaping (RelationValue, RelationValue) -> Bool) {
        self.compare = compare
    }
    
    public func evaluate(_ a: RelationValue, _ b: RelationValue) -> RelationValue {
        return .boolValue(compare(a, b))
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
extension EqualityComparator: CustomStringConvertible {
    public var description: String {
        return "="
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
extension InequalityComparator: CustomStringConvertible {
    public var description: String {
        return "!="
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
extension LTComparator: CustomStringConvertible {
    public var description: String {
        return "<"
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
extension LEComparator: CustomStringConvertible {
    public var description: String {
        return "<="
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
extension GTComparator: CustomStringConvertible {
    public var description: String {
        return ">"
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
extension GEComparator: CustomStringConvertible {
    public var description: String {
        return ">="
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
extension AndComparator: CustomStringConvertible {
    public var description: String {
        return "AND"
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
extension OrComparator: CustomStringConvertible {
    public var description: String {
        return "OR"
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
extension GlobComparator: CustomStringConvertible {
    public var description: String {
        return "GLOB"
    }
}
