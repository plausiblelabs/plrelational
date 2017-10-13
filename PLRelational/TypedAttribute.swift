//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation


/// A type-safe version of an `Attribute`. By default, the attribute name is the conforming type's name.
/// The conforming type specifies a value type which the `Attribute` is expected to hold.
public protocol TypedAttribute {
    /// The value type expected for this attribute.
    associatedtype Value: TypedAttributeValue
    
    /// The underlying untyped `Attribute` for this typed attribute. By default, it's the name of the
    /// conforming type with Swift's little "#1" extras stripped off.
    static var attribute: Attribute { get }
}

public extension TypedAttribute {
    static var attribute: Attribute {
        let s = String(describing: self)
        // Some types get names like "someType #1". Slice off the suffix.
        if let index = s.index(of: " ") {
            return Attribute(String(s[..<index]))
        } else {
            return Attribute(s)
        }
    }
}

/// A type which can be used as the value for a typed attribute. These must be convertible
/// to/from a RelationValue, and must also be Hashable so they can be stored in sets.
public protocol TypedAttributeValue: Hashable {
    /// Make a new instance of this value from a `RelationValue`, and return either
    /// that value or an error.
    static func make(from: RelationValue) -> Result<Self, RelationError>
    
    /// Make a RelationValue that represents this value. Note: it is assumed that all
    /// values can be so represented.
    var toRelationValue: RelationValue { get }
}

/// Errors that can be returned from `TypedAttributeValue.make`
public enum TypedAttributeValueError: RelationError {
    /// The `RelationValue` didn't contain the expected raw type (e.g. provided an int64 instead of text).
    case relationValueTypeMismatch
}

/// When conforming to `RelationValueConvertible`, we'll default to using the
/// implementation of `relationValue` for converting to `RelationValue`.
public extension TypedAttributeValue where Self: RelationValueConvertible {
    var toRelationValue: RelationValue {
        return self.relationValue
    }
}

public extension Row {
    /// Retrieve the value in this row for a given typed attribute, or an error if the value can't
    /// be retrieved or decoded.
    subscript<Attr: TypedAttribute>(attribute: Attr.Type) -> Result<Attr.Value, RelationError> {
        get {
            return Attr.Value.make(from: self[attribute.attribute])
        }
    }
    
    /// Retrieve or set the value in this row for a given typed attribute. On error, nil is
    /// returned. Setting nil for a typed attribute will remove the attribute and value from
    /// the `Row`.
    subscript<Attr: TypedAttribute>(attribute: Attr.Type) -> Attr.Value? {
        get {
            return self[attribute].ok
        }
        set {
            self[attribute.attribute] = newValue?.toRelationValue ?? .notFound
        }
    }
}

extension Int64: TypedAttributeValue {
    public static func make(from: RelationValue) -> Result<Int64, RelationError> {
        return from.int64OrError()
    }
}

extension Double: TypedAttributeValue {
    public static func make(from: RelationValue) -> Result<Double, RelationError> {
        return from.doubleOrError()
    }
}

extension String: TypedAttributeValue {
    public static func make(from: RelationValue) -> Result<String, RelationError> {
        return from.stringOrError()
    }
}

extension Data: TypedAttributeValue {
    public static func make(from: RelationValue) -> Result<Data, RelationError> {
        return from.blobOrError().map(Data.init)
    }
}

/// Helpers for getting specific types out of a `RelationValue`.
private extension RelationValue {
    func typedValueOrError<T>(_ value: T?) -> Result<T, RelationError> {
        return value.map(Result.Ok) ?? .Err(TypedAttributeValueError.relationValueTypeMismatch)
    }
    
    func int64OrError() -> Result<Int64, RelationError> {
        return typedValueOrError(get())
    }
    
    func doubleOrError() -> Result<Double, RelationError> {
        return typedValueOrError(get())
    }
    
    func stringOrError() -> Result<String, RelationError> {
        return typedValueOrError(get())
    }
    
    func blobOrError() -> Result<[UInt8], RelationError> {
        return typedValueOrError(get())
    }
}
