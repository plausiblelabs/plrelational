//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

public struct Attribute {
    /// Note: since InternedUTF8String never deallocates strings,
    /// the number of distinct attributes used in a program must
    /// be bounded. If that ever becomes unacceptable, we'll have
    /// to rework this.
    public var internedName: InternedUTF8String
    
    public var name: String {
        return internedName.string
    }
    
    public init(_ internedName: InternedUTF8String) {
        self.internedName = internedName
    }

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
