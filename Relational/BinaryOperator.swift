//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import sqlite3

public protocol BinaryOperator {
    func evaluate(_ a: RelationValue, _ b: RelationValue) -> RelationValue
}

public struct EqualityComparator: BinaryOperator {
    public init() {}
    
    public func evaluate(_ a: RelationValue, _ b: RelationValue) -> RelationValue {
        return .boolValue(a == b)
    }
}

public struct InequalityComparator: BinaryOperator {
    public init() {}
    
    public func evaluate(_ a: RelationValue, _ b: RelationValue) -> RelationValue {
        return .boolValue(a != b)
    }
}

public struct LTComparator: BinaryOperator {
    public init() {}
    
    public func evaluate(_ a: RelationValue, _ b: RelationValue) -> RelationValue {
        return .boolValue(a < b)
    }
}

public struct LEComparator: BinaryOperator {
    public init() {}
    
    public func evaluate(_ a: RelationValue, _ b: RelationValue) -> RelationValue {
        return .boolValue(a <= b)
    }
}

public struct GTComparator: BinaryOperator {
    public init() {}
    
    public func evaluate(_ a: RelationValue, _ b: RelationValue) -> RelationValue {
        return .boolValue(a > b)
    }
}

public struct GEComparator: BinaryOperator {
    public init() {}
    
    public func evaluate(_ a: RelationValue, _ b: RelationValue) -> RelationValue {
        return .boolValue(a >= b)
    }
}

public struct AndComparator: BinaryOperator {
    public init() {}
    
    public func evaluate(_ a: RelationValue, _ b: RelationValue) -> RelationValue {
        return .boolValue(a.boolValue && b.boolValue)
    }
}

public struct OrComparator: BinaryOperator {
    public init() {}
    
    public func evaluate(_ a: RelationValue, _ b: RelationValue) -> RelationValue {
        return .boolValue(a.boolValue || b.boolValue)
    }
}

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

public struct AnyComparator: BinaryOperator {
    var compare: (RelationValue, RelationValue) -> Bool
    
    public init(_ compare: @escaping (RelationValue, RelationValue) -> Bool) {
        self.compare = compare
    }
    
    public func evaluate(_ a: RelationValue, _ b: RelationValue) -> RelationValue {
        return .boolValue(compare(a, b))
    }
}

extension EqualityComparator: CustomStringConvertible {
    public var description: String {
        return "="
    }
}

extension InequalityComparator: CustomStringConvertible {
    public var description: String {
        return "!="
    }
}

extension LTComparator: CustomStringConvertible {
    public var description: String {
        return "<"
    }
}

extension LEComparator: CustomStringConvertible {
    public var description: String {
        return "<="
    }
}

extension GTComparator: CustomStringConvertible {
    public var description: String {
        return ">"
    }
}

extension GEComparator: CustomStringConvertible {
    public var description: String {
        return ">="
    }
}

extension AndComparator: CustomStringConvertible {
    public var description: String {
        return "AND"
    }
}

extension OrComparator: CustomStringConvertible {
    public var description: String {
        return "OR"
    }
}

extension GlobComparator: CustomStringConvertible {
    public var description: String {
        return "GLOB"
    }
}
