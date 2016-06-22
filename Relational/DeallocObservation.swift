//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

/// Observe the deallocation of an object.
///
/// - parameter target: The object to observe.
/// - parameter f: The function to call when `target` is deallocated.
/// - returns: A removal function. Call this to remove the observation before `target` has been deallocated.
public func ObserveDeallocation(target: AnyObject, _ f: Void -> Void) -> (Void -> Void) {
    lock.lock()
    defer { lock.unlock() }
    
    let callOnDeinit: CallOnDeinit
    if let obj = objc_getAssociatedObject(target, key) as? CallOnDeinit {
        callOnDeinit = obj
    } else {
        callOnDeinit = CallOnDeinit()
        objc_setAssociatedObject(target, key, callOnDeinit, .OBJC_ASSOCIATION_RETAIN)
    }
    
    let counter = callOnDeinit.counter
    callOnDeinit.counter += 1
    
    callOnDeinit.calls[counter] = f
    
    return { [weak callOnDeinit] in
        lock.lock()
        defer { lock.unlock() }
        callOnDeinit?.calls.removeValueForKey(counter)
    }
}

private class CallOnDeinit {
    var counter: UInt64 = 0
    var calls: [UInt64: Void -> Void] = [:]
    
    deinit {
        for (_, call) in calls {
            call()
        }
    }
}

private let lock = NSLock()
private let key = malloc(1)
