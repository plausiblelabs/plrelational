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
    
    public init(onLock: () -> Void, onUnlock: () -> Void) {
        self.onLock = onLock
        self.onUnlock = onUnlock
    }

    /// Notes that a change is coming.  If the change count goes to 1, `onLock` will be invoked.
    /// Must be called on UI thread.
    public func willChange() {
        changeCount += 1
        if changeCount == 1 {
            onLock()
        }
    }
    
    /// Notes that a change has occurred.  If the change count goes to 0, `onUnlock` will be invoked.
    /// Must be called on UI thread.
    public func didChange() {
        precondition(changeCount > 0)
        
        changeCount -= 1
        if changeCount == 0 {
            onUnlock()
        }
    }
}
