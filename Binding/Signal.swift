//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

public typealias ObserverRemoval = Void -> Void

public struct ChangeMetadata {
    public let transient: Bool
    
    public init(transient: Bool) {
        self.transient = transient
    }
}

public struct SignalObserver<T> {
    public let valueWillChange: () -> Void
    public let valueChanging: (change: T, metadata: ChangeMetadata) -> Void
    public let valueDidChange: () -> Void
    
    public init(
        valueWillChange: () -> Void,
        valueChanging: (change: T, metadata: ChangeMetadata) -> Void,
        valueDidChange: () -> Void)
    {
        self.valueWillChange = valueWillChange
        self.valueChanging = valueChanging
        self.valueDidChange = valueDidChange
    }
    
    public func valueChanging(change: T, transient: Bool = false) {
        valueChanging(change: change, metadata: ChangeMetadata(transient: transient))
    }
}

public protocol SignalType: class {
    associatedtype Value
    
    /// Converts this instance into a concrete `Signal`.
    var signal: Signal<Value> { get }
    
    /// The current change count (incremented by will-change and decremented by did-change).
    var changeCount: Int { get }
    
    func start()
    func observe(observer: SignalObserver<Value>) -> ObserverRemoval
}

public class Signal<T>: SignalType {
    public typealias Value = T
    public typealias Observer = SignalObserver<T>
    public typealias Notify = SignalObserver<T>

    public private(set) var changeCount = 0
    private var observers: [UInt64: Observer] = [:]
    private var nextObserverID: UInt64 = 0
    
    internal init() {
    }
    
    public static func pipe() -> (Signal, Notify) {
        let signal = Signal()
        let notify = SignalObserver(
            valueWillChange: signal.notifyWillChange,
            valueChanging: signal.notifyChanging,
            valueDidChange: signal.notifyDidChange
        )
        return (signal, notify)
    }

    public var signal: Signal<T> {
        return self
    }
    
    public func start() {
    }
    
    public func observe(observer: Observer) -> ObserverRemoval {
        let id = nextObserverID
        nextObserverID += 1
        observers[id] = observer
        return { self.observers.removeValueForKey(id) }
    }

    /// Convenience form of `observe` that builds an Observer whose `valueWillChange` and `valueDidChange`
    /// handlers pass through to `notify`, but uses the given `valueChanging` handler.
    public func observe<U>(notify: SignalObserver<U>, _ valueChanging: (change: T, metadata: ChangeMetadata) -> Void) -> ObserverRemoval {
        return self.observe(SignalObserver(
            valueWillChange: notify.valueWillChange,
            valueChanging: valueChanging,
            valueDidChange: notify.valueDidChange
        ))
    }
    
    /// Convenience form of `observe` that builds an Observer whose `valueWillChange` and `valueDidChange`
    /// are no-ops, but uses the given `valueChanging` handler.
    public func observe(valueChanging: (change: T, metadata: ChangeMetadata) -> Void) -> ObserverRemoval {
        return self.observe(SignalObserver(
            valueWillChange: {},
            valueChanging: valueChanging,
            valueDidChange: {}
        ))
    }

    internal func notifyWillChange() {
        changeCount += 1
        for (_, observer) in observers {
            observer.valueWillChange()
        }
    }

    internal func notifyChanging(change: T, metadata: ChangeMetadata) {
        for (_, observer) in observers {
            observer.valueChanging(change: change, metadata: metadata)
        }
    }

    internal func notifyDidChange() {
        precondition(changeCount > 0)
        changeCount -= 1
        for (_, observer) in observers {
            observer.valueDidChange()
        }
    }

    // For testing purposes only.
    internal var observerCount: Int { return observers.count }
}
