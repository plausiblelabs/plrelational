//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//


import Foundation

/// A simple mutex with a Swifty API. Note: despite being a struct, it acts like a reference type.
public struct Mutex {
    fileprivate let lock = NSLock()
    
    /// Call the given function with the lock locked, automatically unlocking before returning or throwing.
    public func locked<T>(_ f: (Void) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try f()
    }
}

/// A wrapper that holds a value and a mutex, and allows accessing that value with the mutex held.
/// When the wrapped type is a reference type, this will act like a reference type. When the
/// wrapped type is a value type, this will act weirdly, with the mutex being shared among copies
/// but the value being separate in each copy. This struct really shouldn't be copied, just have one.
public struct Mutexed<T> {
    fileprivate let mutex = Mutex()
    
    fileprivate var value: T
    
    public init(_ value: T) {
        self.value = value
    }
    
    /// Call the given function with the lock locked, passing in the value so it can be used while locked.
    public func withValue<Result>(_ f: (T) throws -> Result) rethrows -> Result {
        return try mutex.locked({
            return try f(value)
        })
    }
    
    /// Call the given function with the lock locked, passing in the value as inout so it can be used or
    /// mutated while locked.
    public mutating func withMutableValue<Result>(f: (inout T) throws -> Result) rethrows -> Result {
        return try mutex.locked({
            return try f(&value)
        })
    }
    
    /// Fetch the wrapped value. Obviously, only use this when it's safe to use (but not necessarily fetch)
    /// the value without locking, like with value types.
    public func get() -> T {
        return withValue({ $0 })
    }
}
