//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation


public protocol DispatchContext {
    func async(f: Void -> Void)
}

extension CFRunLoopRef: DispatchContext {
    public func async(f: Void -> Void) {
        if CFRunLoopGetCurrent() === self {
            f()
        } else {
            CFRunLoopPerformBlock(self, kCFRunLoopCommonModes, f)
            CFRunLoopWakeUp(self)
        }
    }
}

public struct DispatchQueueContext: DispatchContext {
    var queue: dispatch_queue_t
    
    public init(queue: dispatch_queue_t) {
        self.queue = queue
    }
    
    public func async(f: Void -> Void) {
        dispatch_async(queue, f)
    }
}

extension DispatchQueueContext {
    public static var main: DispatchQueueContext {
        return DispatchQueueContext(queue: dispatch_get_main_queue())
    }
}


public struct DispatchContextWrapped<T> {
    var context: DispatchContext
    var wrapped: T
    
    init(context: DispatchContext, wrapped: T) {
        self.context = context
        self.wrapped = wrapped
    }
    
    public func withWrapped(f: T -> Void) {
        context.async({
            f(self.wrapped)
        })
    }
}
