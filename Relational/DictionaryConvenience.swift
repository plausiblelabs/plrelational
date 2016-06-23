//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

extension Dictionary where Value: Hashable {
    var reversed: [Value: Key] {
        return Dictionary<Value, Key>(self.map({ ($1, $0) }))
    }
}

extension Dictionary {
    mutating func getOrCreate(key: Key, @autoclosure defaultValue: Void -> Value) -> Value {
        if let value = self[key] {
            return value
        } else {
            let new = defaultValue()
            self[key] = new
            return new
        }
    }
}

/// Combine two dictionaries. Any keys that exist in both dictionaries will
/// have the value from the second dictionary in the result.
func +<K: Hashable, V>(a: [K: V], b: [K: V]) -> [K: V] {
    var result = a
    for (k, v) in b {
        result[k] = v
    }
    return result
}
