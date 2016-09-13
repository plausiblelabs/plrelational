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
    func schedule(_ action: @escaping () -> Void) -> Disposable?
}

/// A scheduler that performs all work synchronously.
public final class ImmediateScheduler: Scheduler {
    public init() {}
    
    public func schedule(_ action: @escaping () -> Void) -> Disposable? {
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
    private static var __once: () = {
            DispatchQueue.main.setSpecific(key: UIScheduler.dispatchSpecificKey, value: true)
        }()
    fileprivate static var dispatchSpecificKey = DispatchSpecificKey<Bool>()
    
    fileprivate var queueLength: Int32 = 0
    
    public init() {
        _ = UIScheduler.__once
    }
    
    public func schedule(_ action: @escaping () -> Void) -> Disposable? {
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
        if queued == 1 && (DispatchQueue.getSpecific(key: UIScheduler.dispatchSpecificKey) ?? false) {
            actionAndDecrement()
        } else {
            DispatchQueue.main.async(execute: actionAndDecrement)
        }
        
        return disposable
    }
}

/// A scheduler backed by a serial GCD queue.
public final class QueueScheduler: Scheduler {
    internal let queue: DispatchQueue
    
    internal init(internalQueue: DispatchQueue) {
        queue = internalQueue
    }
    
    /// A singleton QueueScheduler that always targets the main thread's GCD
    /// queue.
    ///
    /// Unlike UIScheduler, this scheduler supports scheduling for a future
    /// date, and will always schedule asynchronously (even if already running
    /// on the main thread).
    public static let mainQueueScheduler = QueueScheduler(internalQueue: DispatchQueue.main)
    
    /// Initializes a scheduler that will target a new serial
    /// queue with the given quality of service class.
    public convenience init(qos: DispatchQoS.QoSClass = DispatchQoS.QoSClass.default, name: String = "Binding.QueueScheduler") {
        self.init(internalQueue: DispatchQueue(label: name, attributes: dispatch_queue_attr_make_with_qos_class(DispatchQueue.Attributes(), qos, 0)))
    }
    
    public func schedule(_ action: @escaping () -> Void) -> Disposable? {
        let d = SimpleDisposable()
        
        queue.async {
            if !d.disposed {
                action()
            }
        }
        
        return d
    }
}
