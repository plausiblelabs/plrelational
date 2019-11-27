//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Darwin

/// :nodoc: Implementation detail (will be made non-public eventually)
/// An interned string that can be efficiently hashed and compared for equality by
/// just examining a pointer. These strings are never deallocated so the total number
/// of distinct ones used in a program run must be bounded.
extension InternedUTF8String {
    private static var lock = pthread_mutex_t()
    private static var strings: [InternedUTF8String.Data: InternedUTF8String] = {
        pthread_mutex_init(&lock, nil)
        return [:]
    }()
    
    /// Get an interned string corresponding to some UTF-8 data, creating it if necessary.
    public static func get(_ data: InternedUTF8String.Data) -> InternedUTF8String {
        pthread_mutex_lock(&lock)
        defer { pthread_mutex_unlock(&lock) }
        
        if let str = strings[data] {
            return str
        } else {
            let str = InternedUTF8String(data)
            let permanentData = InternedUTF8String.Data(ptr: str.utf8, length: str.length)
            strings[permanentData] = str
            return str
        }
    }
    
    /// Get an interned string corresponding to a String, creating it if necessary.
    public static func get(_ string: String) -> InternedUTF8String {
        return string.precomposedStringWithCanonicalMapping.withCString({
            let length = Int(strlen($0))
            return $0.withMemoryRebound(to: UInt8.self, capacity: length, {
                let data = InternedUTF8String.Data(ptr: $0, length: length)
                return get(data)
            })
        })
    }
}

/// :nodoc: Implementation detail (will be made non-public eventually)
public struct InternedUTF8String: Hashable, Comparable {
    private struct Header {
        static var size: Int {
            return MemoryLayout<Header>.size
        }
        
        var length: Int
        var string: String
    }
    
    private var ptr: UnsafeRawPointer
    
    init(_ data: InternedUTF8String.Data) {
        let ptr = malloc(Header.size + data.length)!
        memcpy(ptr + Header.size, data.ptr, data.length)
        let str = String(bytesNoCopy: ptr + Header.size, length: data.length, encoding: .utf8, freeWhenDone: false)!
        ptr.bindMemory(to: Header.self, capacity: 1).initialize(to: Header(length: data.length, string: str))
        
        self.ptr = UnsafeRawPointer(ptr)
    }
    
    /// Get the length of the string, in UTF-8 bytes.
    public var length: Int {
        return ptr.bindMemory(to: Header.self, capacity: 1).pointee.length
    }
    
    /// Get the String that corresponds to this value. This is precomputed,
    /// and therefore efficient.
    public var string: String {
        return ptr.bindMemory(to: Header.self, capacity: 1).pointee.string
    }
    
    /// Get the pointer to this string's UTF-8 data. Note: not NUL terminated.
    public var utf8: UnsafePointer<UInt8> {
        return (ptr + Header.size).bindMemory(to: UInt8.self, capacity: length)
    }
    
    public static func ==(lhs: InternedUTF8String, rhs: InternedUTF8String) -> Bool {
        return lhs.ptr == rhs.ptr
    }
    
    public static func <(lhs: InternedUTF8String, rhs: InternedUTF8String) -> Bool {
        let result = memcmp(lhs.utf8, rhs.utf8, min(lhs.length, rhs.length))
        if result < 0 {
            return true
        } else if result > 0 {
            return false
        } else {
            return lhs.length < rhs.length
        }
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ptr)
    }
}

/// :nodoc: Implementation detail (will be made non-public eventually)
extension InternedUTF8String {
    public struct Data: Hashable {
        var ptr: UnsafePointer<UInt8>
        var length: Int
        var hash: Int
        
        init(ptr: UnsafePointer<UInt8>, length: Int) {
            self.ptr = ptr
            self.length = length
            
            var hash: UInt64 = 14695981039346656037
            Data.updateHash(&hash, pointer: ptr, length: length)
            self.hash = Int(truncatingIfNeeded: hash)
        }
        
        public static func ==(lhs: Data, rhs: Data) -> Bool {
            return lhs.hash == rhs.hash && lhs.length == rhs.length && memcmp(lhs.ptr, rhs.ptr, lhs.length) == 0
        }
        
        // TODO: This was migrated from the pre-Swift-4.2 `hashValue` approach to use `Hasher`, but
        // could probably be rewritten in a better way
        public func hash(into hasher: inout Hasher) {
            hasher.combine(hash)
        }
        
        private static func updateHash(_ hash: inout UInt64, pointer: UnsafePointer<UInt8>, length: Int) {
            // FNV-1a hash: http://www.isthe.com/chongo/tech/comp/fnv/#FNV-1a
            let fnvPrime: UInt64 = 1099511628211
            
            for i in 0 ..< length {
                hash = hash ^ UInt64(pointer[i])
                hash = hash &* fnvPrime
            }
        }
    }
}
