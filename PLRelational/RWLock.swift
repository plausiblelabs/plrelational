//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Darwin


/// A reader-writer lock. Wraps pthread_rwlock.
class RWLock {
    var lock: UnsafeMutablePointer<pthread_rwlock_t>
    
    init() {
        lock = UnsafeMutablePointer.allocate(capacity: 1)
        let err = pthread_rwlock_init(lock, nil)
        if err != 0 {
            fatalError("pthread_rwlock_init returned error \(err): \(String(cString: strerror(err)) )")
        }
    }
    
    deinit {
        let err = pthread_rwlock_destroy(lock)
        if err != 0 {
            fatalError("pthread_rwlock_destroy returned error \(err): \(String(cString: strerror(err)) )")
        }
        lock.deallocate(capacity: 1)
    }
    
    func readLock() {
        pthread_rwlock_rdlock(lock)
    }
    
    func writeLock() {
        pthread_rwlock_wrlock(lock)
    }
    
    func unlock() {
        pthread_rwlock_unlock(lock)
    }
    
    func read<T>(_ f: (Void) -> T) -> T {
        readLock()
        defer { unlock() }
        return f()
    }
    
    func write<T>(_ f: (Void) -> T) -> T {
        writeLock()
        defer { unlock() }
        return f()
    }
}
