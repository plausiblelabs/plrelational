//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//


import Foundation

class InlineMutableData: ManagedBuffer<(length: Int, capacity: Int, hash: UInt64), UInt8> {
    static func make(capacity: Int) -> Self {
        func cast<T, U>(val: T) -> U { return val as! U }
        
        let obj = create(capacity, initialValue: { _ in (length: 0, capacity: capacity, hash: 0) })
        return cast(obj)
    }
    
    static func append<T: InlineMutableData>(data: T, pointer: UnsafePointer<UInt8>, length: Int) -> T {
        if data.tryAppend(pointer, length: length) {
            return data
        }
        
        let existingLength = data.value.length
        let neededCapacity = existingLength + length
        let existingCapacity = data.value.capacity
        let newCapacity = max(neededCapacity, existingCapacity * 2)
        
        let newObj = T.make(newCapacity)
        data.withUnsafeMutablePointerToElements({ elements in
            let success = newObj.tryAppend(elements, length: existingLength)
            precondition(success, "tryAppend should never fail copying into a brand new object with the right size")
        })
        
        let success = newObj.tryAppend(pointer, length: length)
        precondition(success, "tryAppend should never fail copying into a brand new object with the right size")
        return newObj
    }
    
    static func append<T: InlineMutableData, U>(data: T, untypedPointer pointer: UnsafePointer<U>, length: Int) -> T {
        return append(data, pointer: UnsafePointer(pointer), length: length)
    }
    
    final func updateHash(inout hash: UInt64, pointer: UnsafePointer<UInt8>, length: Int) {
        // FNV-1a hash: http://www.isthe.com/chongo/tech/comp/fnv/#FNV-1a
        let fnvPrime: UInt64 = 1099511628211
        
        for i in 0 ..< length {
            hash = hash ^ UInt64(pointer[i])
            hash = hash &* fnvPrime
        }
    }
    
    final func tryAppend(pointer: UnsafePointer<UInt8>, length: Int) -> Bool {
        let remainingCapacity = self.value.capacity - self.value.length
        if length <= remainingCapacity {
            withUnsafeMutablePointers({ valuePtr, elementPtr in
                if pointer != nil {
                    memcpy(elementPtr + valuePtr.memory.length, pointer, length)
                }
                valuePtr.memory.length += length
                valuePtr.memory.hash = 0
            })
            return true
        } else {
            return false
        }
    }
    
    final var length: Int {
        return value.length
    }
}

extension InlineMutableData: Hashable {
    var hashValue: Int {
        return withUnsafeMutablePointers({ valuePtr, elementPtr in
            if valuePtr.memory.hash == 0 {
                objc_sync_enter(self)
                if valuePtr.memory.hash == 0 {
                    var newHash: UInt64 = 14695981039346656037
                    self.updateHash(&newHash, pointer: elementPtr, length: valuePtr.memory.length)
                    valuePtr.memory.hash = newHash
                }
            }
            objc_sync_exit(self)
            return Int(bitPattern: UInt(truncatingBitPattern: valuePtr.memory.hash))
        })
    }
}

func ==(lhs: InlineMutableData, rhs: InlineMutableData) -> Bool {
    if lhs.value.length != rhs.value.length || lhs.value.hash != rhs.value.hash {
        return false
    }
    
    let memcmpResult = lhs.withUnsafeMutablePointerToElements({ lhsElements in
        rhs.withUnsafeMutablePointerToElements({ rhsElements in
            memcmp(lhsElements, rhsElements, lhs.value.length)
        })
    })
    return memcmpResult == 0
}

extension InlineMutableData: CustomStringConvertible {
    var description: String {
        return withUnsafeMutablePointers({ valuePtr, elementPtr in
            let data = NSData(bytes: elementPtr, length: valuePtr.memory.length)
            return "InlineMutableData(length: \(valuePtr.memory.length), capacity: \(valuePtr.memory.capacity), hash: \(valuePtr.memory.hash)) \(data.description)"
        })
    }
}