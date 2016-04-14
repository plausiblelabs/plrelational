
extension Dictionary where Value: Hashable {
    var reversed: [Value: Key] {
        return Dictionary<Value, Key>(self.map({ ($1, $0) }))
    }
}

func +<K: Hashable, V>(a: [K: V], b: [K: V]) -> [K: V] {
    var result = a
    for (k, v) in b {
        result[k] = v
    }
    return result
}
