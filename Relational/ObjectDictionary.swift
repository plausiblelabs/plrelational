
/// Like Dictionary, but the keys use object identity rather than value equality.
struct ObjectDictionary<Key: AnyObject, Value>: SequenceType, DictionaryLiteralConvertible {
    private var dict: Dictionary<ObjectSetWrapper<Key>, Value>
    
    init<S: SequenceType where S.Generator.Element == (Key, Value)>(_ seq: S) {
        dict = Dictionary(seq.map({ (ObjectSetWrapper(object: $0), $1) }))
    }
    
    init(dictionaryLiteral elements: (Key, Value)...) {
        self.init(elements)
    }
    
    func generate() -> AnyGenerator<(Key, Value)> {
        let gen = dict.lazy.map({ ($0.object, $1) }).generate()
        return AnyGenerator(gen)
    }
    
    subscript(key: Key) -> Value? {
        get {
            return dict[ObjectSetWrapper(object: key)]
        }
        set {
            dict[ObjectSetWrapper(object: key)] = newValue
        }
    }
    
    mutating func getOrCreate(key: Key, @autoclosure defaultValue: Void -> Value) -> Value {
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
}
