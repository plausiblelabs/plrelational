//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Darwin
import Foundation

/// A map from object instances to arbitrary values, based on object identity.
/// Similar to ObjectDictionary, but this is a mutable reference type rather
/// than a value type, and it uses its own hash table implementation rather
/// than borrowing Dictionary's. This makes it much faster as it skips a lot
/// of overhead involved in indirecting through Hashable/Equatable.
class ObjectMap<Value> {
    typealias Bucket = (key: Int, value: Value)
    
    var count: Int = 0
    var capacity: Int
    
    var table: UnsafeMutablePointer<Bucket>
    
    init() {
        capacity = 16
        table = ObjectMap.allocate(capacity)
    }
    
    deinit {
        deallocate(table, capacity)
    }
    
    private func deallocate(table: UnsafeMutablePointer<Bucket>, _ capacity: Int) {
        for index in 0..<capacity {
            let ptr = table + index
            if ptr.memory.key != 0 {
                ptr.destroy()
            }
        }
        free(table)
    }
    
    private static func allocate(count: Int) -> UnsafeMutablePointer<Bucket> {
        return UnsafeMutablePointer<Bucket>(calloc(count, strideof(Bucket.self)))
    }
    
    private func keyForObject(obj: AnyObject) -> Int {
        return unsafeBitCast(obj, Int.self)
    }
    
    private func indexForKey(key: Int, _ table: UnsafeMutablePointer<Bucket>, _ capacity: Int) -> Int {
        // Objects are 16-byte aligned, so shift off the last four bits to get a better hash value.
        // If this ends up being wrong this code will still work, but hash collisions will be more
        // frequent so performance will suffer.
        let hash = key >> 4
        var index = hash % capacity
        while table[index].key != key && table[index].key != 0 {
            index = (index + 1) % capacity
        }
        return index
    }
    
    private func setValue(value: Value, key: Int, table: UnsafeMutablePointer<Bucket>, _ capacity: Int) {
        let index = indexForKey(key, table, capacity)
        table[index].key = key
        table[index].value = value
    }
    
    private func reallocateIfNecessary() {
        if Double(count) / Double(capacity) > 0.75 {
            let newCapacity = capacity * 2
            let newTable = ObjectMap.allocate(newCapacity)
            for index in 0..<capacity {
                let key = table[index].key
                if key != 0 {
                    let newIndex = indexForKey(key, newTable, newCapacity)
                    (newTable + newIndex).moveInitializeFrom(table + index, count: 1)
                }
            }
            free(table)
            table = newTable
            capacity = newCapacity
        }
    }
    
    subscript(obj: AnyObject) -> Value? {
        get {
            let key = keyForObject(obj)
            let index = indexForKey(key, table, capacity)
            return table[index].key == key ? table[index].value : nil
        }
        set {
            reallocateIfNecessary()
            let key = keyForObject(obj)
            let index = indexForKey(key, table, capacity)
            if let newValue = newValue {
                if table[index].key == key {
                    table[index].value = newValue
                } else {
                    (table + index).initialize((key, newValue))
                    count += 1
                }
            } else {
                (table + index).destroy()
                table[index].key = 0
            }
        }
    }
    
    func getOrCreate(obj: AnyObject, @autoclosure defaultValue: Void -> Value) -> Value {
        reallocateIfNecessary()
        let key = keyForObject(obj)
        let index = indexForKey(key, table, capacity)
        if table[index].key == key {
            return table[index].value
        } else {
            let newValue = defaultValue()
            (table + index).initialize((key, newValue))
            count += 1
            return newValue
        }
    }
}
