//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

/// :nodoc:
public protocol DispatchContext {
    func async(_ f: @escaping (Void) -> Void)
}

/// :nodoc:
extension CFRunLoop: DispatchContext {
    public func async(_ f: @escaping (Void) -> Void) {
        async(inModes: [.commonModes], f)
    }
    
    public func async(inModes: [CFRunLoopMode], _ f: @escaping (Void) -> Void) {
        let cfmodes = inModes.map({ $0.rawValue }) as CFArray
        CFRunLoopPerformBlock(self, cfmodes, f)
        CFRunLoopWakeUp(self)
    }
}


/// :nodoc:
public struct RunLoopDispatchContext: DispatchContext {
    public var runloop: CFRunLoop
    
    /// When this is true, calls to `async` on the thread belonging to `runloop` are executed
    /// immediately inline, rather than being delayed to the next runloop cycle. Sorry, I
    /// couldn't come up with a good name. It's not really async when that happens, but it's
    /// sometimes useful.
    public var executeReentrantImmediately: Bool
    
    public var modes: [CFRunLoopMode]
    
    public init(runloop: CFRunLoop = CFRunLoopGetCurrent(), executeReentrantImmediately: Bool = true, modes: [CFRunLoopMode] = [.commonModes]) {
        self.runloop = runloop
        self.executeReentrantImmediately = executeReentrantImmediately
        self.modes = modes
    }
    
    public func async(_ f: @escaping (Void) -> Void) {
        if executeReentrantImmediately && CFRunLoopGetCurrent() === runloop {
            f()
        } else {
            runloop.async(inModes: modes, f)
        }
    }
}

/// :nodoc:
/// A simple dispatch context that just makes the calls immediately inline. This is not really
/// "async" but it's sometimes useful.
public struct DirectDispatchContext: DispatchContext {
    public init() {
    }
    
    public func async(_ f: @escaping (Void) -> Void) {
        f()
    }
}

/// :nodoc:
public struct DispatchQueueContext: DispatchContext {
    public var queue: DispatchQueue
    
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

/// :nodoc:
extension DispatchQueueContext {
    public static var main: DispatchQueueContext {
        return DispatchQueueContext(queue: DispatchQueue.main)
    }
}


/// :nodoc:
public struct DispatchContextWrapped<T> {
    public var context: DispatchContext
    public var wrapped: T
    
    init(context: DispatchContext, wrapped: T) {
        self.context = context
        self.wrapped = wrapped
    }
    
    public func withWrapped(_ f: @escaping (T) -> Void) {
        context.async({
            f(self.wrapped)
        })
    }
}

/// :nodoc:
extension DispatchContext {
    public func wrap<T>(_ value: T) -> DispatchContextWrapped<T> {
        return DispatchContextWrapped(context: self, wrapped: value)
    }
}
