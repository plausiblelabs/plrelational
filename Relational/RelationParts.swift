
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

extension Attribute: StringLiteralConvertible {
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
}

extension Scheme: ArrayLiteralConvertible {
    public init(arrayLiteral elements: Attribute...) {
        attributes = Set(elements)
    }
}

extension Scheme: Equatable {}
public func ==(a: Scheme, b: Scheme) -> Bool {
    return a.attributes == b.attributes
}

public struct Row: Hashable {
    public var values: [Attribute: RelationValue]
    
    public init(values: [Attribute: RelationValue]) {
        self.values = values
    }
    
    public var hashValue: Int {
        // Note: needs to ensure the same value is produced regardless of order, so no fancy stuff.
        return values.map({ $0.0.hashValue ^ $0.1.hashValue }).reduce(0, combine: ^)
    }
    
    public subscript(attribute: Attribute) -> RelationValue {
        get {
            return values[attribute] ?? .NotFound
        }
        set {
            values[attribute] = newValue
        }
    }
    
    public func renameAttributes(renames: [Attribute: Attribute]) -> Row {
        return Row(values: Dictionary(values.map({ attribute, value in
            let newAttribute = renames[attribute] ?? attribute
            return (newAttribute, value)
        })))
    }
    
    /// Create a new row containing only the values whose attributes are also in the attributes parameter.
    public func rowWithAttributes<Seq: SequenceType where Seq.Generator.Element == Attribute>(attributes: Seq) -> Row {
        return Row(values: Dictionary(attributes.flatMap({
            if let value = self.values[$0] {
                return ($0, value)
            } else {
                return nil
            }
        })))
    }
}

extension Row: DictionaryLiteralConvertible {
    public init(dictionaryLiteral elements: (Attribute, RelationValue)...) {
        values = Dictionary(elements)
    }
}

public func ==(a: Row, b: Row) -> Bool {
    return a.values == b.values
}
