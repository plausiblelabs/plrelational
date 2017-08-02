//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

/// :nodoc: Implementation detail (will be made non-public eventually)
extension Dictionary where Value: Hashable {
    public var inverted: [Value: Key] {
        return Dictionary<Value, Key>(self.map({ ($1, $0) }))
    }
}

/// :nodoc: Implementation detail (will be made non-public eventually)
extension Dictionary {
    public mutating func getOrCreate(_ key: Key, defaultValue: @autoclosure (Void) -> Value) -> Value {
        if let value = self[key] {
            return value
        } else {
            let new = defaultValue()
            self[key] = new
            return new
        }
    }
    
    public subscript(key: Key, defaultValue defaultValue: @autoclosure (Void) -> Value) -> Value {
        mutating get {
            return getOrCreate(key, defaultValue: defaultValue())
        }
        set {
            self[key] = newValue
        }
    }
}

/// :nodoc: Implementation detail (will be made non-public eventually)
/// Combine a dictionary and some collection of key/value pairs, which may be a second dictionary.
/// Any keys that exist in both will have the value from the second parameter in the result.
public func +<K: Hashable, V, Seq: Sequence>(a: [K: V], b: Seq) -> [K: V] where Seq.Iterator.Element == (K, V) {
    var result = a
    for (k, v) in b {
        result[k] = v
    }
    return result
}

/// :nodoc: Implementation detail (will be made non-public eventually)
extension Dictionary {
    /// Initialize a dictionary with an array of key/value pairs.
    public init(_ pairs: [(Key, Value)]) {
        self.init(minimumCapacity: pairs.count)
        
        for (k, v) in pairs {
            self[k] = v
        }
    }
}
