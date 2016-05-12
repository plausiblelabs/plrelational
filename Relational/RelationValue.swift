
/// Values which can be stored in a Relation. These are just the SQLite data types,
/// Plus a "not found" value for when an attribute doesn't exist at all.
/// We might want to do our own thing and not hew so closely to SQLite's way....
public enum RelationValue {
    case NULL
    case Integer(Int64)
    case Real(Double)
    case Text(String)
    case Blob([UInt8])
    
    case NotFound
}

extension RelationValue: Equatable {}
public func ==(a: RelationValue, b: RelationValue) -> Bool {
    switch (a, b) {
    case (.NULL, .NULL): return true
    case (.Integer(let a), .Integer(let b)): return a == b
    case (.Real(let a), .Real(let b)): return a == b
    case (.Text(let a), .Text(let b)): return a == b
    case (.Blob(let a), .Blob(let b)): return a == b
    case (.NotFound, .NotFound): return true
    default: return false
    }
}

extension RelationValue: Comparable {}
public func <(a: RelationValue, b: RelationValue) -> Bool {
    // Since this must provide a total ordering, sort in the order of the case statements.
    // By doing the checks in order, we ensure the wildcards only catch later cases, not
    // earlier ones.
    switch (a, b) {
    case (.NULL, .NULL): return false
    case (.NULL, _): return true
    case (_, .NULL): return false
        
    case (.Integer(let a), .Integer(let b)): return a < b
    case (.Integer, _): return true
    case (_, .Integer): return false
        
    case (.Real(let a), .Real(let b)): return a < b
    case (.Real, _): return true
    case (_, .Real): return false
        
    case (.Text(let a), .Text(let b)): return a < b
    case (.Text, _): return true
    case (_, .Text): return false
        
    case (.Blob(let a), .Blob(let b)): return a.lexicographicalCompare(b)
    case (.Blob, _): return true
    case (_, .Blob): return false
        
    case (.NotFound, .NotFound): return false
    case (.NotFound, _): return true
    case (_, .NotFound): return false
        
    default: fatalError("This should never execute, it's just here because the compiler can't seem to figure out that the previous cases are exhaustive")
    }
}

extension RelationValue: Hashable {
    public var hashValue: Int {
        switch self {
        case .NULL: return 0
        case .Integer(let x): return 1 ^ x.hashValue
        case .Real(let x): return 2 ^ x.hashValue
        case .Text(let x): return 3 ^ x.hashValue
        case .Blob(let x): return 4 ^ x.hashValueFromElements
        case .NotFound: return 5
        }
    }
}

extension RelationValue: CustomStringConvertible {
    public var description: String {
        switch self {
        case .NULL: return "NULL"
        case .Integer(let x): return String(x)
        case .Real(let x): return String(x)
        case .Text(let x): return String(x)
        case .Blob(let x): return String(x)
        case .NotFound: return "<value not found>"
        }
    }
}

extension RelationValue {
    public init(_ int: Int64) {
        self = .Integer(int)
    }
    
    public init(_ real: Double) {
        self = .Real(real)
    }
    
    public init(_ text: String) {
        self = .Text(text)
    }
    
    public init(_ blob: [UInt8]) {
        self = .Blob(blob)
    }
}

extension RelationValue: StringLiteralConvertible {
    public init(extendedGraphemeClusterLiteral value: String) {
        self = .Text(value)
    }
    
    public init(unicodeScalarLiteral value: String) {
        self = .Text(value)
    }
    
    public init(stringLiteral value: String) {
        self = .Text(value)
    }
}

extension RelationValue: IntegerLiteralConvertible {
    public init(integerLiteral value: Int64) {
        self = .Integer(value)
    }
}

extension RelationValue {
    public func get() -> Int64? {
        switch self {
        case .Integer(let x): return x
        default: return nil
        }
    }

    public func get() -> Double? {
        switch self {
        case .Real(let x): return x
        default: return nil
        }
    }

    public func get() -> String? {
        switch self {
        case .Text(let x): return x
        default: return nil
        }
    }
    
    public func get() -> [UInt8]? {
        switch self {
        case .Blob(let x): return x
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
    var boolValue: Bool {
        return self != .Integer(0)
    }
    
    static func boolValue(value: Bool) -> RelationValue {
        return .Integer(value ? 1 : 0)
    }
}
