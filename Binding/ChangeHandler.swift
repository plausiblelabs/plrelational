//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

/// Works in conjunction with will-change and did-change notifications that are delivered to
/// a UI control when an associated Property's underlying value is changing asynchronously.
public class ChangeHandler {
    
    private let onLock: () -> Void
    private let onUnlock: () -> Void
    private var changeCount: Int = 0

    public init() {
        self.onLock = {}
        self.onUnlock = {}
    }

    public init(onLock: () -> Void, onUnlock: () -> Void) {
        self.onLock = onLock
        self.onUnlock = onUnlock
    }
    
    /// Increments the change count by the given amount.  If the change count goes from 0 to >= 1, `onLock`
    /// will be invoked.  Must be called on UI thread.
    public func incrementCount(inc: Int) {
        precondition(inc >= 0)
        if inc == 0 { return }
        
        let wasZero = changeCount == 0
        changeCount += inc
        if wasZero {
            onLock()
        }
    }

    /// Decrements the change count by the given amount.  If the change count goes to 0, `onUnlock`
    /// will be invoked.  Must be called on UI thread.
    public func decrementCount(dec: Int) {
        precondition(dec >= 0)
        precondition(changeCount - dec >= 0)
        if dec == 0 { return }
        
        changeCount -= dec
        if changeCount == 0 {
            onUnlock()
        }
    }

    /// Notes that a change is coming.  If the change count goes to 1, `onLock` will be invoked.
    /// Must be called on UI thread.
    public func willChange() {
        incrementCount(1)
    }
    
    /// Notes that a change has occurred.  If the change count goes to 0, `onUnlock` will be invoked.
    /// Must be called on UI thread.
    public func didChange() {
        decrementCount(1)
    }
}
