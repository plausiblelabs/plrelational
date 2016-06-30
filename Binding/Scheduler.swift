//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//
// This is based in part on the `Scheduler` API from ReactiveCocoa:
// https://github.com/ReactiveCocoa/ReactiveCocoa
// Copyright (c) 2014 GitHub. All rights reserved.
//

import Foundation

/// Represents a serial queue of work items.
public protocol Scheduler {
    /// Enqueues an action on the scheduler.
    ///
    /// When the work is executed depends on the scheduler in use.
    ///
    /// Optionally returns a disposable that can be used to cancel the work
    /// before it begins.
    func schedule(action: () -> Void) -> Disposable?
}

/// A scheduler that performs all work synchronously.
public final class ImmediateScheduler: Scheduler {
    public init() {}
    
    public func schedule(action: () -> Void) -> Disposable? {
        action()
        return nil
    }
}

/// A scheduler that performs all work on the main queue, as soon as possible.
///
/// If the caller is already running on the main queue when an action is
/// scheduled, it may be run synchronously. However, ordering between actions
/// will always be preserved.
public final class UIScheduler: Scheduler {
    private static var dispatchOnceToken: dispatch_once_t = 0
    private static var dispatchSpecificKey: UInt8 = 0
    private static var dispatchSpecificContext: UInt8 = 0
    
    private var queueLength: Int32 = 0
    
    public init() {
        dispatch_once(&UIScheduler.dispatchOnceToken) {
            dispatch_queue_set_specific(
                dispatch_get_main_queue(),
                &UIScheduler.dispatchSpecificKey,
                &UIScheduler.dispatchSpecificContext,
                nil
            )
        }
    }
    
    public func schedule(action: () -> Void) -> Disposable? {
        let disposable = SimpleDisposable()
        let actionAndDecrement = {
            if !disposable.disposed {
                action()
            }
            
            OSAtomicDecrement32(&self.queueLength)
        }
        
        let queued = OSAtomicIncrement32(&queueLength)
        
        // If we're already running on the main queue, and there isn't work
        // already enqueued, we can skip scheduling and just execute directly.
        if queued == 1 && dispatch_get_specific(&UIScheduler.dispatchSpecificKey) == &UIScheduler.dispatchSpecificContext {
            actionAndDecrement()
        } else {
            dispatch_async(dispatch_get_main_queue(), actionAndDecrement)
        }
        
        return disposable
    }
}

/// A scheduler backed by a serial GCD queue.
public final class QueueScheduler: Scheduler {
    internal let queue: dispatch_queue_t
    
    internal init(internalQueue: dispatch_queue_t) {
        queue = internalQueue
    }
    
    /// A singleton QueueScheduler that always targets the main thread's GCD
    /// queue.
    ///
    /// Unlike UIScheduler, this scheduler supports scheduling for a future
    /// date, and will always schedule asynchronously (even if already running
    /// on the main thread).
    public static let mainQueueScheduler = QueueScheduler(internalQueue: dispatch_get_main_queue())
    
    /// Initializes a scheduler that will target a new serial
    /// queue with the given quality of service class.
    public convenience init(qos: dispatch_qos_class_t = QOS_CLASS_DEFAULT, name: String = "Binding.QueueScheduler") {
        self.init(internalQueue: dispatch_queue_create(name, dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, qos, 0)))
    }
    
    public func schedule(action: () -> Void) -> Disposable? {
        let d = SimpleDisposable()
        
        dispatch_async(queue) {
            if !d.disposed {
                action()
            }
        }
        
        return d
    }
}
