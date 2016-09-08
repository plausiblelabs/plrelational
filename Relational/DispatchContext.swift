//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation


public protocol DispatchContext {
    func async(_ f: (Void) -> Void)
}

extension CFRunLoop: DispatchContext {
    public func async(_ f: @escaping (Void) -> Void) {
        CFRunLoopPerformBlock(self, CFRunLoopMode.commonModes as CFTypeRef!, f)
        CFRunLoopWakeUp(self)
    }
}


public struct RunLoopDispatchContext: DispatchContext {
    var runloop: CFRunLoop
    
    /// When this is true, calls to `async` on the thread belonging to `runloop` are executed
    /// immediately inline, rather than being delayed to the next runloop cycle. Sorry, I
    /// couldn't come up with a good name. It's not really async when that happens, but it's
    /// sometimes useful.
    var executeReentrantImmediately: Bool
    
    public init(runloop: CFRunLoop = CFRunLoopGetCurrent(), executeReentrantImmediately: Bool = true) {
        self.runloop = runloop
        self.executeReentrantImmediately = executeReentrantImmediately
    }
    
    public func async(_ f: @escaping (Void) -> Void) {
        if executeReentrantImmediately && CFRunLoopGetCurrent() === runloop {
            f()
        } else {
            runloop.async(f)
        }
    }
}

/// A simple dispatch context that just makes the calls immediately inline. This is not really
/// "async" but it's sometimes useful.
public struct DirectDispatchContext: DispatchContext {
    public func async(_ f: (Void) -> Void) {
        f()
    }
}

public struct DispatchQueueContext: DispatchContext {
    var queue: DispatchQueue
    
    public init(queue: DispatchQueue) {
        self.queue = queue
    }
    
    public init(newSerialQueueNamed label: String) {
        self.init(queue: DispatchQueue(label: label, attributes: []))
    }
    
    public func async(_ f: @escaping (Void) -> Void) {
        queue.async(execute: f)
    }
}

extension DispatchQueueContext {
    public static var main: DispatchQueueContext {
        return DispatchQueueContext(queue: DispatchQueue.main)
    }
}


public struct DispatchContextWrapped<T> {
    var context: DispatchContext
    var wrapped: T
    
    init(context: DispatchContext, wrapped: T) {
        self.context = context
        self.wrapped = wrapped
    }
    
    public func withWrapped(_ f: (T) -> Void) {
        context.async({
            f(self.wrapped)
        })
    }
}
