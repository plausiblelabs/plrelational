//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

/// Like Dictionary, but the keys use object identity rather than value equality.
struct ObjectDictionary<Key: AnyObject, Value>: Sequence, ExpressibleByDictionaryLiteral {
    fileprivate var dict: Dictionary<ObjectSetWrapper<Key>, Value>
    
    init<S: Sequence>(_ seq: S) where S.Iterator.Element == (Key, Value) {
        dict = Dictionary(seq.map({ (ObjectSetWrapper(object: $0), $1) }))
    }
    
    init(dictionaryLiteral elements: (Key, Value)...) {
        self.init(elements)
    }
    
    func makeIterator() -> AnyIterator<(Key, Value)> {
        let gen = dict.lazy.map({ ($0.object, $1) }).makeIterator()
        return AnyIterator(gen)
    }
    
    subscript(key: Key) -> Value? {
        get {
            return dict[ObjectSetWrapper(object: key)]
        }
        set {
            dict[ObjectSetWrapper(object: key)] = newValue
        }
    }
    
    subscript(key: Key, defaultValue defaultValue: @autoclosure () -> Value) -> Value {
        mutating get {
            return getOrCreate(key, defaultValue: defaultValue())
        }
        set {
            self[key] = newValue
        }
    }
    
    mutating func getOrCreate(_ key: Key, defaultValue: @autoclosure () -> Value) -> Value {
        if let value = self[key] {
            return value
        } else {
            let new = defaultValue()
            self[key] = new
            return new
        }
    }
    
    var keys: [Key] {
        return dict.keys.map({ $0.object })
    }
    
    var isEmpty: Bool {
        return dict.isEmpty
    }
}
