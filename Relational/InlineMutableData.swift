//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//


import Darwin

class InlineMutableData: ManagedBuffer<(length: Int, capacity: Int, hash: UInt64), UInt8> {
    static func make(capacity: Int) -> Self {
        func cast<T, U>(val: T) -> U { return val as! U }
        
        let obj = create(capacity, initialValue: { _ in (length: 0, capacity: capacity, hash: 14695981039346656037) })
        return cast(obj)
    }
    
    static func append(inout data: InlineMutableData, pointer: UnsafePointer<UInt8>, length: Int) {
        if data.tryAppend(pointer, length: length) {
            return
        }
        
        let existingLength = data.value.length
        let neededCapacity = existingLength + length
        let existingCapacity = data.value.capacity
        let newCapacity = max(neededCapacity, existingCapacity * 2)
        
        let newObj = make(newCapacity)
        data.withUnsafeMutablePointerToElements({ elements in
            let success = newObj.tryAppend(elements, length: existingLength)
            precondition(success, "tryAppend should never fail copying into a brand new object with the right size")
        })
        
        data = newObj
        let success = data.tryAppend(pointer, length: length)
        precondition(success, "tryAppend should never fail copying into a brand new object with the right size")
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
            withUnsafeMutablePointers({ value, elements in
                memcpy(elements + value.memory.length, pointer, length)
                value.memory.length += length
                self.updateHash(&value.memory.hash, pointer: pointer, length: length)
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
        return Int(UInt(truncatingBitPattern: value.hash))
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
