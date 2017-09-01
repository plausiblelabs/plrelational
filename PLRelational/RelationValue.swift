//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

/// Values which can be stored in a Relation. These are just the SQLite data types,
/// Plus a "not found" value for when an attribute doesn't exist at all.
/// We might want to do our own thing and not hew so closely to SQLite's way....
public enum RelationValue {
    /// The null value. Note that unlike SQL, our null is equal to itself.
    case null
    
    /// A 64-bit signed integer.
    case integer(Int64)
    
    /// A 64-bit floating point value.
    case real(Double)
    
    /// A string.
    case text(String)
    
    /// A byte array.
    case blob([UInt8])
    
    /// A special value used to indicate that a `Row` has no value for a given attribute.
    /// Not intended to be persisted or provided by `Relation`s.
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
        case .integer(let x): return DJBHash.hash(values: [1, x.hashValue])
        case .real(let x): return DJBHash.hash(values: [2, x.hashValue])
        case .text(let x): return DJBHash.hash(values: [3, x.hashValue])
        case .blob(let x): return DJBHash.hash(values: [4, x.hashValueFromElements])
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

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
public protocol RelationValueConvertible {
    var relationValue: RelationValue { get }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
extension RelationValue: RelationValueConvertible {
    public var relationValue: RelationValue {
        return self
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
extension String: RelationValueConvertible {
    public var relationValue: RelationValue {
        return RelationValue(self)
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
extension Int: RelationValueConvertible {
    public var relationValue: RelationValue  {
        return RelationValue(Int64(self))
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
extension Int64: RelationValueConvertible {
    public var relationValue: RelationValue {
        return RelationValue(self)
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
extension Double: RelationValueConvertible {
    public var relationValue: RelationValue {
        return RelationValue(self)
    }
}

/// :nodoc: Elided from docs to reduce clutter for now; part of "official" API but may be reworked in the near future
extension Bool: RelationValueConvertible {
    public var relationValue: RelationValue {
        return RelationValue.boolValue(self)
    }
}

extension RelationValue {
    /// Create a new integer value.
    public init(_ int: Int64) {
        self = .integer(int)
    }
    
    /// Create a new floating point value.
    public init(_ real: Double) {
        self = .real(real)
    }
    
    /// Create a new text value.
    public init(_ text: String) {
        self = .text(text)
    }
    
    /// Create a new byte array value.
    public init(_ blob: [UInt8]) {
        self = .blob(blob)
    }
    
    /// Create a new byte array value from the contents of `data`.
    public init(_ data: Data) {
        let count = data.count
        self = data.withUnsafeBytes({
            .blob(Array(UnsafeBufferPointer(start: $0, count: count)))
        })
    }
    
    /// Create a new byte array value from the contents of `sequence`.
    public init<Seq: Sequence>(_ sequence: Seq) where Seq.Iterator.Element == UInt8 {
        self = .blob(Array(sequence))
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
    /// Get the underlying integer value, or nil if the value is not an integer.
    public func get() -> Int64? {
        switch self {
        case .integer(let x): return x
        default: return nil
        }
    }

    /// Get the underlying floating point value, or nil if the value is not floating point.
    public func get() -> Double? {
        switch self {
        case .real(let x): return x
        default: return nil
        }
    }

    /// Get the underlying string value, or nil if the value is not an string.
    public func get() -> String? {
        switch self {
        case .text(let x): return x
        default: return nil
        }
    }
    
    /// Get the underlying byte array value, or nil if the value is not an byte array.
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
    
    /// Create a new integer value from a boolean. The result is `1` for `true` and `0` for `false`.
    public static func boolValue(_ value: Bool) -> RelationValue {
        return .integer(value ? 1 : 0)
    }
}
