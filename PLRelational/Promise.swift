//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

/// :nodoc:
/// A simple implementation of a promise. You can set a value and wait for a value to be set.
/// Thread safe, obviously.
public class Promise<T> {
    private let condition = NSCondition()
    private var value: T? = nil
    
    public init() {}
    
    public func fulfill(_ value: T) {
        condition.lock()
        precondition(self.value == nil)
        self.value = value
        condition.broadcast()
        condition.unlock()
    }
    
    public func get() -> T {
        condition.lock()
        while true {
            if let value = self.value {
                condition.unlock()
                return value
            } else {
                condition.wait()
            }
        }
    }
}
