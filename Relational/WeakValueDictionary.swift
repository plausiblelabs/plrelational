
/// How many operations to perform between scrubs.
private let scrubInterval = 10

/// How many indexes to scrub when starting from the current position.
private let inPositionScrubCount = 5

/// How many indexes to scrub when starting from the beginning of the dictionary.
private let beginningScrubCount = 2

struct WeakValueDictionary<Key: Hashable, Value: AnyObject> {
    var underlyingDictionary: [Key: WeakReference<Value>] = [:]
    
    var scrubOperationCount = 0
    
    subscript(key: Key) -> Value? {
        get {
            return underlyingDictionary[key]?.value
        }
        set {
            if let newValue = newValue {
                underlyingDictionary[key] = WeakReference(value: newValue)
            } else {
                underlyingDictionary.removeValueForKey(key)
            }
        }
    }
    
    private mutating func scrubIfNeeded(key: Key) {
        scrubOperationCount += 1
        if scrubOperationCount >= scrubInterval {
            // Scrub starting from key, and also from the beginning of the dictionary.
            // The beginning will be less frequently seen than the rest of the dictionary
            // because we can't iterate backwards, so it gets a bit of special attention.
            // Otherwise if we built up a dictionary that started with a bunch of nil
            // values, they'd never get seen and evicted.
            if let index = underlyingDictionary.indexForKey(key) {
                scrub(startingFrom: index, count: inPositionScrubCount)
            }
            scrub(startingFrom: underlyingDictionary.startIndex, count: beginningScrubCount)
        }
    }
    
    /// Scan a few elements in the dictionary looking for nil values to evict.
    private mutating func scrub(startingFrom index: DictionaryIndex<Key, WeakReference<Value>>, count: Int) {
        var keysToEvict: [Key] = []
        
        var index = index
        for _ in 0..<count {
            if index == underlyingDictionary.endIndex {
                break
            }
            
            let (key, value) = underlyingDictionary[index]
            if value.value == nil {
                keysToEvict.append(key)
            }
            
            index = index.successor()
        }
        
        for key in keysToEvict {
            underlyingDictionary.removeValueForKey(key)
        }
    }
}
