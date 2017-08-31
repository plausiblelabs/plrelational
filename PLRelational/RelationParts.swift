//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

/// A key used to describe `Relation` schemes and map keys to values in `Row`.
/// Note: `Attribute` is implemented internally using interned strings. This
/// means that two equal `Attributes` always have the same storage. This cuts
/// down on storage overhead and allows equality to be implemented as pointer
/// equality. However, the interned strings cannot be destroyed when no longer
/// in use. Because of this, a program must not created an unlimited number of
/// distinct `Attribute`s.
public struct Attribute {
    /// The underlying interned string representing the `Attribute`.
    public var internedName: InternedUTF8String
    
    /// The `String` name of this `Attribute`.
    public var name: String {
        return internedName.string
    }
    
    /// Create a new `Attribute` from an interned string.
    public init(_ internedName: InternedUTF8String) {
        self.internedName = internedName
    }
    
    /// Create a new `Attribute` from a string.
    public init(_ name: String) {
        self.internedName = .get(name)
    }
}

extension Attribute: Hashable, Comparable {
    public var hashValue: Int {
        return internedName.hashValue
    }
}

public func ==(a: Attribute, b: Attribute) -> Bool {
    return a.internedName == b.internedName
}

public func <(a: Attribute, b: Attribute) -> Bool {
    return a.internedName < b.internedName
}

extension Attribute: CustomStringConvertible {
    public var description: String {
        return name
    }
}

extension Attribute: ExpressibleByStringLiteral {
    public init(extendedGraphemeClusterLiteral value: String) {
        self.init(value)
    }
    
    public init(unicodeScalarLiteral value: String) {
        self.init(value)
    }
    
    public init(stringLiteral value: String) {
        self.init(value)
    }
}

public struct Scheme {
    public var attributes: Set<Attribute> = []
    
    public init(attributes: Set<Attribute>) {
        self.attributes = attributes
    }
}

extension Scheme: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Attribute...) {
        attributes = Set(elements)
    }
}

extension Scheme: Equatable {}
public func ==(a: Scheme, b: Scheme) -> Bool {
    return a.attributes == b.attributes
}

extension Scheme: CustomStringConvertible {
    public var description: String {
        return String(describing: attributes.sorted())
    }
}
