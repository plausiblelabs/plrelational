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
    
    fileprivate(set) var count: Int = 0
    fileprivate var deadCount: Int = 0
    fileprivate var capacity: Int
    
    var table: UnsafeMutablePointer<Bucket>
    
    init(capacity: Int = 16) {
        self.capacity = max(capacity, 16)
        table = ObjectMap.allocate(self.capacity)
    }
    
    deinit {
        deallocate(table, capacity)
    }
    
    fileprivate func deallocate(_ table: UnsafeMutablePointer<Bucket>, _ capacity: Int) {
        for index in 0..<capacity {
            let ptr = table + index
            let key = ptr.pointee.key
            // Destroy all entries that aren't empty or dead
            if key != EMPTY && key != DEAD {
                ptr.deinitialize()
            }
        }
        free(table)
    }
    
    fileprivate static func allocate(_ count: Int) -> UnsafeMutablePointer<Bucket> {
        return calloc(count, MemoryLayout<Bucket>.stride).bindMemory(to: Bucket.self, capacity: count)
    }
    
    fileprivate func keyForObject(_ obj: AnyObject) -> Int {
        return unsafeBitCast(obj, to: Int.self)
    }
    
    fileprivate func indexForKey(_ key: Int, _ table: UnsafeMutablePointer<Bucket>, _ capacity: Int) -> (firstEmptyOrMatch: Int, firstDead: Int?) {
        // Objects are 16-byte aligned, so shift off the last four bits to get a better hash value.
        // If this ends up being wrong this code will still work, but hash collisions will be more
        // frequent so performance will suffer.
        // Perform the shift as an unsigned number, to avoid producing indexes with
        // negative values.
        let hash = Int(bitPattern: UInt(bitPattern: key) >> 4)
        var index = hash % capacity
        var firstDead: Int? = nil
        while table[index].key != key && table[index].key != EMPTY {
            if table[index].key == DEAD {
                firstDead = index
            }
            index = (index + 1) % capacity
        }
        return (index, firstDead)
    }
    
    // Right now (2016-06-17) there is a duplicate symbol error on this func when whole module
    // optimization is enabled. Marking it final prevents that, somehow.
    fileprivate final func reallocateIfNecessary() {
        if Double(count) / Double(capacity) > 0.75 {
            reallocateToSize(capacity * 2)
        } else if Double(count + deadCount) / Double(capacity) > 0.75 {
            reallocateToSize(capacity)
        }
    }
    
    // This one also causes a duplicate symbol error somehow.
    fileprivate final func reallocateToSize(_ newCapacity: Int) {
        let newTable = ObjectMap.allocate(newCapacity)
        for index in 0..<capacity {
            let key = table[index].key
            if key != EMPTY && key != DEAD {
                let (newIndex, _) = indexForKey(key, newTable, newCapacity)
                (newTable + newIndex).moveInitialize(from: table + index, count: 1)
            }
        }
        free(table)
        table = newTable
        capacity = newCapacity
        deadCount = 0
    }
    
    subscript(obj: AnyObject) -> Value? {
        get {
            let key = keyForObject(obj)
            let (index, _) = indexForKey(key, table, capacity)
            return table[index].key == key ? table[index].value : nil
        }
        set {
            reallocateIfNecessary()
            let key = keyForObject(obj)
            let (firstEmptyOrMatch, firstDead) = indexForKey(key, table, capacity)
            if let newValue = newValue {
                if table[firstEmptyOrMatch].key == key {
                    table[firstEmptyOrMatch].value = newValue
                } else {
                    let index = firstDead ?? firstEmptyOrMatch
                    (table + index).initialize(to: (key, newValue))
                    count += 1
                    if firstDead != nil {
                        deadCount -= 1
                    }
                }
            } else {
                let index = firstEmptyOrMatch
                if table[index].key == key {
                    (table + index).deinitialize()
                    table[index].key = DEAD
                    count -= 1
                    deadCount += 1
                }
            }
        }
    }
    
    func getOrCreate(_ obj: AnyObject, defaultValue: @autoclosure () -> Value) -> Value {
        reallocateIfNecessary()
        let key = keyForObject(obj)
        let (firstEmptyOrMatch, firstDead) = indexForKey(key, table, capacity)
        if table[firstEmptyOrMatch].key == key {
            return table[firstEmptyOrMatch].value
        } else {
            let index = firstDead ?? firstEmptyOrMatch
            let newValue = defaultValue()
            (table + index).initialize(to: (key, newValue))
            count += 1
            if firstDead != nil {
                deadCount -= 1
            }
            return newValue
        }
    }
}

/// Key value used to indicate empty buckets.
private let EMPTY = 0

/// Key value used to indicate dead buckets. These are buckets which once had
/// an object but no longer do. They can be reused for new storage, but can't
/// be used as a termination point when searching for a key.
private let DEAD = -1

extension ObjectMap: CustomDebugStringConvertible {
    var debugDescription: String {
        let initialLine = "count=\(count) deadCount=\(deadCount) capacity=\(capacity) table=\(table)"
        let tableLines = (0 ..< capacity).map({ (i: Int) -> String in
            let bucket = table[i]
            let key = bucket.key
            if key == EMPTY {
                return String(format: "[%ld] EMPTY", i)
            } else if key == DEAD {
                return String(format: "[%ld] DEAD", i)
            } else {
                let bucketString = String(describing: bucket.value) as NSString
                return String(format: "[%ld] %p = %@ (%@)", i, key, bucketString, key)
            }
        })
        
        return ([initialLine] + tableLines).joined(separator: "\n")
    }
}
