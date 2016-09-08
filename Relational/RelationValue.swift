//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

/// Values which can be stored in a Relation. These are just the SQLite data types,
/// Plus a "not found" value for when an attribute doesn't exist at all.
/// We might want to do our own thing and not hew so closely to SQLite's way....
public enum RelationValue {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob([UInt8])
    
    case notFound
}

extension RelationValue: Equatable {}
public func ==(a: RelationValue, b: RelationValue) -> Bool {
    switch (a, b) {
    case (.null, .null): return true
    case (.integer(let a), .integer(let b)): return a == b
    case (.real(let a), .real(let b)): return a == b
    case (.text(let a), .text(let b)): return a == b
    case (.blob(let a), .blob(let b)): return a == b
    case (.notFound, .notFound): return true
    default: return false
    }
}

extension RelationValue: Comparable {}
public func <(a: RelationValue, b: RelationValue) -> Bool {
    // Since this must provide a total ordering, sort in the order of the case statements.
    // By doing the checks in order, we ensure the wildcards only catch later cases, not
    // earlier ones.
    switch (a, b) {
    case (.null, .null): return false
    case (.null, _): return true
    case (_, .null): return false
        
    case (.integer(let a), .integer(let b)): return a < b
    case (.integer, _): return true
    case (_, .integer): return false
        
    case (.real(let a), .real(let b)): return a < b
    case (.real, _): return true
    case (_, .real): return false
        
    case (.text(let a), .text(let b)): return a < b
    case (.text, _): return true
    case (_, .text): return false
        
    case (.blob(let a), .blob(let b)): return a.lexicographicallyPrecedes(b)
    case (.blob, _): return true
    case (_, .blob): return false
        
    case (.notFound, .notFound): return false
    case (.notFound, _): return true
    case (_, .notFound): return false
        
    default: fatalError("This should never execute, it's just here because the compiler can't seem to figure out that the previous cases are exhaustive")
    }
}

extension RelationValue: Hashable {
    public var hashValue: Int {
        switch self {
        case .null: return 0
        case .integer(let x): return 1 ^ x.hashValue
        case .real(let x): return 2 ^ x.hashValue
        case .text(let x): return 3 ^ x.hashValue
        case .blob(let x): return 4 ^ x.hashValueFromElements
        case .notFound: return 5
        }
    }
}

extension RelationValue: CustomStringConvertible {
    public var description: String {
        switch self {
        case .null: return "NULL"
        case .integer(let x): return String(x)
        case .real(let x): return String(x)
        case .text(let x): return String(x)
        case .blob(let x): return String(describing: x)
        case .notFound: return "<value not found>"
        }
    }
}

extension RelationValue {
    public init(_ int: Int64) {
        self = .integer(int)
    }
    
    public init(_ real: Double) {
        self = .real(real)
    }
    
    public init(_ text: String) {
        self = .text(text)
    }
    
    public init(_ blob: [UInt8]) {
        self = .blob(blob)
    }
}

extension RelationValue: ExpressibleByStringLiteral {
    public init(extendedGraphemeClusterLiteral value: String) {
        self = .text(value)
    }
    
    public init(unicodeScalarLiteral value: String) {
        self = .text(value)
    }
    
    public init(stringLiteral value: String) {
        self = .text(value)
    }
}

extension RelationValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int64) {
        self = .integer(value)
    }
}

extension RelationValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .real(value)
    }
}

extension RelationValue {
    public func get() -> Int64? {
        switch self {
        case .integer(let x): return x
        default: return nil
        }
    }

    public func get() -> Double? {
        switch self {
        case .real(let x): return x
        default: return nil
        }
    }

    public func get() -> String? {
        switch self {
        case .text(let x): return x
        default: return nil
        }
    }
    
    public func get() -> [UInt8]? {
        switch self {
        case .blob(let x): return x
        default: return nil
        }
    }
}

extension RelationValue {
    /// Interpret the value as a boolean, producing either true or false.
    /// SQLite has weird rules about true and false: it converts the value
    /// to a number (if it isn't already) and then considers 0 to be false.
    /// That means that, for example, the string "0" is false. For now,
    /// we'll skip that and just say that Integer(0) is the only false.
    public var boolValue: Bool {
        return self != .integer(0)
    }
    
    static func boolValue(_ value: Bool) -> RelationValue {
        return .integer(value ? 1 : 0)
    }
}
