//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//


import Foundation

class InlineMutableData: ManagedBuffer<(length: Int, capacity: Int, hash: UInt64), UInt8> {
    static func make(_ capacity: Int) -> Self {
        func cast<T, U>(_ val: T) -> U { return val as! U }
        
        let obj = create(minimumCapacity: capacity, makingHeaderWith: { _ in (length: 0, capacity: capacity, hash: 0) })
        return cast(obj)
    }
    
    static func append<T: InlineMutableData>(_ data: T, pointer: UnsafeRawPointer?, length: Int) -> T {
        if data.tryAppend(pointer, length: length) {
            return data
        }
        
        let existingLength = data.header.length
        let neededCapacity = existingLength + length
        let existingCapacity = data.header.capacity
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
    
    static func append<T: InlineMutableData, U>(_ data: T, untypedPointer pointer: UnsafePointer<U>, length: Int) -> T {
        return pointer.withMemoryRebound(to: UInt8.self, capacity: length, { append(data, pointer: $0, length: length) })
    }
    
    final func updateHash(_ hash: inout UInt64, pointer: UnsafePointer<UInt8>, length: Int) {
        // FNV-1a hash: http://www.isthe.com/chongo/tech/comp/fnv/#FNV-1a
        let fnvPrime: UInt64 = 1099511628211
        
        for i in 0 ..< length {
            hash = hash ^ UInt64(pointer[i])
            hash = hash &* fnvPrime
        }
    }
    
    final func tryAppend(_ pointer: UnsafeRawPointer?, length: Int) -> Bool {
        let remainingCapacity = self.header.capacity - self.header.length
        if length <= remainingCapacity {
            withUnsafeMutablePointers({ headerPtr, elementPtr in
                if pointer != nil {
                    memcpy(elementPtr + headerPtr.pointee.length, pointer, length)
                }
                headerPtr.pointee.length += length
                headerPtr.pointee.hash = 0
            })
            return true
        } else {
            return false
        }
    }
    
    final var length: Int {
        return header.length
    }
}

extension InlineMutableData: Hashable {
    var hashValue: Int {
        return withUnsafeMutablePointers({ headerPtr, elementPtr in
            // No thread safety. Will still work correctly, but may redundantly calculate
            // the hash more than once if multiple threads hit this simultaneously.
            if headerPtr.pointee.hash == 0 {
                var newHash: UInt64 = 14695981039346656037
                self.updateHash(&newHash, pointer: elementPtr, length: headerPtr.pointee.length)
                headerPtr.pointee.hash = newHash
            }
            return Int(bitPattern: UInt(truncatingBitPattern: headerPtr.pointee.hash))
        })
    }
}

func ==(lhs: InlineMutableData, rhs: InlineMutableData) -> Bool {
    if lhs.header.length != rhs.header.length || lhs.header.hash != rhs.header.hash {
        return false
    }
    
    let memcmpResult = lhs.withUnsafeMutablePointerToElements({ lhsElements in
        rhs.withUnsafeMutablePointerToElements({ rhsElements in
            memcmp(lhsElements, rhsElements, lhs.header.length)
        })
    })
    return memcmpResult == 0
}

extension InlineMutableData: CustomStringConvertible {
    var description: String {
        return withUnsafeMutablePointers({ headerPtr, elementPtr in
            let data = Data(bytes: UnsafePointer<UInt8>(elementPtr), count: headerPtr.pointee.length)
            return "InlineMutableData(length: \(headerPtr.pointee.length), capacity: \(headerPtr.pointee.capacity), hash: \(headerPtr.pointee.hash)) \(data.description)"
        })
    }
}
