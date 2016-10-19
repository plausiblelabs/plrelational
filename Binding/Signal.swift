//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

public typealias ObserverRemoval = (Void) -> Void

public struct ChangeMetadata {
    public let transient: Bool
    
    public init(transient: Bool) {
        self.transient = transient
    }
}

public struct SignalObserver<T> {
    public let valueWillChange: () -> Void
    public let valueChanging: (_ change: T, _ metadata: ChangeMetadata) -> Void
    public let valueDidChange: () -> Void
    
    public init(
        valueWillChange: @escaping () -> Void,
        valueChanging: @escaping (_ change: T, _ metadata: ChangeMetadata) -> Void,
        valueDidChange: @escaping () -> Void)
    {
        self.valueWillChange = valueWillChange
        self.valueChanging = valueChanging
        self.valueDidChange = valueDidChange
    }
    
    public func valueChanging(_ change: T, transient: Bool = false) {
        valueChanging(change, ChangeMetadata(transient: transient))
    }
}

public protocol SignalType: class {
    associatedtype Value
    
    /// Converts this instance into a concrete `Signal`.
    var signal: Signal<Value> { get }
    
    /// The current change count (incremented by will-change and decremented by did-change).
    var changeCount: Int { get }
    
    /// Causes the underlying signal to start delivering values.
    func start(deliverInitial: Bool)
    
    /// Registers the given observer, which will be notified when the signal delivers new values.
    func observe(_ observer: SignalObserver<Value>) -> ObserverRemoval
}

open class Signal<T>: SignalType {
    public typealias Value = T
    public typealias Observer = SignalObserver<T>
    public typealias Notify = SignalObserver<T>

    open private(set) var changeCount: Int
    private let startFunc: (Bool) -> Void
    private var started = false
    
    private var observers: [UInt64: Observer] = [:]
    private var nextObserverID: UInt64 = 0
    
    internal init(changeCount: Int, startFunc: @escaping (Bool) -> Void) {
        self.changeCount = changeCount
        self.startFunc = startFunc
    }
    
    open static func pipe(initialValue: T? = nil) -> (Signal, Notify) {
        let signal = PipeSignal(initialValue: initialValue)
        let notify = SignalObserver(
            valueWillChange: signal.notifyWillChange,
            valueChanging: signal.notifyChanging,
            valueDidChange: signal.notifyDidChange
        )
        return (signal, notify)
    }

    open var signal: Signal<T> {
        return self
    }

    public final func start(deliverInitial: Bool) {
        if !started {
            started = true
            startImpl(deliverInitial: deliverInitial)
        }
    }
    
    /// Invokes the provided startFunc by default, but subclasses can override for custom start behavior.
    internal func startImpl(deliverInitial: Bool) {
        startFunc(deliverInitial)
    }
    
    open func observe(_ observer: Observer) -> ObserverRemoval {
        let id = nextObserverID
        nextObserverID += 1
        observers[id] = observer
        return { self.observers.removeValue(forKey: id) }
    }

    /// Convenience form of `observe` that builds an Observer whose `valueWillChange` and `valueDidChange`
    /// handlers pass through to `notify`, but uses the given `valueChanging` handler.
    open func observe<U>(_ notify: SignalObserver<U>, _ valueChanging: @escaping (_ change: T, _ metadata: ChangeMetadata) -> Void) -> ObserverRemoval {
        return self.observe(SignalObserver(
            valueWillChange: notify.valueWillChange,
            valueChanging: valueChanging,
            valueDidChange: notify.valueDidChange
        ))
    }
    
    /// Convenience form of `observe` that builds an Observer whose `valueWillChange` and `valueDidChange`
    /// are no-ops, but uses the given `valueChanging` handler.
    open func observe(_ valueChanging: @escaping (_ change: T, _ metadata: ChangeMetadata) -> Void) -> ObserverRemoval {
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

    internal func notifyChanging(_ change: T, metadata: ChangeMetadata) {
        for (_, observer) in observers {
            observer.valueChanging(change, metadata)
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

private class PipeSignal<T>: Signal<T> {
    let initialValue: T?
    
    fileprivate init(initialValue: T?) {
        self.initialValue = initialValue
        super.init(changeCount: 0, startFunc: { _ in })
    }
    
    override func startImpl(deliverInitial: Bool) {
        if deliverInitial {
            if let initial = initialValue {
                notifyWillChange()
                notifyChanging(initial, metadata: ChangeMetadata(transient: false))
                notifyDidChange()
            }
        }
    }
}

internal func isRepeat<T>(_ v0: T, v1: T) -> Bool {
    return false
}

internal func isRepeat<T: Equatable>(_ v0: T, v1: T) -> Bool {
    return v0 == v1
}

internal func isRepeat<T>(_ v0: T?, v1: T?) -> Bool {
    return false
}

internal func isRepeat<T: Equatable>(_ v0: T?, v1: T?) -> Bool {
    return v0 == v1
}
