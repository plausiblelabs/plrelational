//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

public struct Attribute {
    public var name: String
    
    public init(_ name: String) {
        self.name = name
    }
}

extension Attribute: Hashable, Comparable {
    public var hashValue: Int {
        return name.hashValue
    }
}

public func ==(a: Attribute, b: Attribute) -> Bool {
    return a.name == b.name
}

public func <(a: Attribute, b: Attribute) -> Bool {
    return a.name < b.name
}

extension Attribute: CustomStringConvertible {
    public var description: String {
        return name
    }
}

extension Attribute: ExpressibleByStringLiteral {
    public init(extendedGraphemeClusterLiteral value: String) {
        name = value
    }
    
    public init(unicodeScalarLiteral value: String) {
        name = value
    }
    
    public init(stringLiteral value: String) {
        name = value
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
