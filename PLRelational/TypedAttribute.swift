//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation


public protocol TypedAttribute {
    associatedtype Value: TypedAttributeValue
    
    static var name: Attribute { get }
}

public extension TypedAttribute {
    static var name: Attribute {
        let s = String(describing: self)
        // Some types get names like "someType #1". Slice off the suffix.
        if let index = s.index(of: " ") {
            return Attribute(String(s[..<index]))
        } else {
            return Attribute(s)
        }
    }
}

public protocol TypedAttributeValue: Hashable {
    static func make(from: RelationValue) -> Result<Self, RelationError>
    var toRelationValue: RelationValue { get }
}

public enum TypedAttributeValueError: RelationError {
    case relationValueTypeMismatch
}

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

public extension TypedAttributeValue where Self: RelationValueConvertible {
    var toRelationValue: RelationValue {
        return self.relationValue
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
