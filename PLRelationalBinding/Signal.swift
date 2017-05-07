//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

public typealias ObserverRemoval = () -> Void

public struct ChangeMetadata {
    public let transient: Bool
    
    public init(transient: Bool) {
        self.transient = transient
    }
}

/// An event delivered to a SignalObserver.  Note that "synchronous" signals must only
/// deliver `valueChanging` events, while "asynchronous" signals can send a
/// `beginPossibleAsyncChange` event to signal that a new value *may* be forthcoming via
/// `valueChanging`.  The underlying signal is not *required* to deliver a `valueChanging`
/// after a `begin`, but every `begin` must be balanced by an `end`.
public enum SignalEvent<T> {
    case beginPossibleAsyncChange
    case valueChanging(T, ChangeMetadata)
    case endPossibleAsyncChange
}

/// An observer that responds to events delivered by a Signal.
public struct SignalObserver<T> {
    public let onEvent: (SignalEvent<T>) -> Void

    public init(onEvent: @escaping (SignalEvent<T>) -> Void) {
        self.onEvent = onEvent
    }
    
    /// Convenience initializer that only accepts `valueChanging` events.
    /// Any other events are considered a fatal error.  This is mainly useful
    /// in cases where the observed signal is expected to be fully synchronous,
    /// i.e., always delivers changes immediately.
    public init(synchronousValueChanging: @escaping (T, ChangeMetadata) -> Void) {
        self.init(onEvent: { event in
            switch event {
            case .beginPossibleAsyncChange, .endPossibleAsyncChange:
                fatalError("Asynchronous events not allowed")
            case let .valueChanging(value, metadata):
                synchronousValueChanging(value, metadata)
            }
        })
    }
    
    /// Convenience initializer for compatibility with earlier structure.
    public init(
        valueWillChange: @escaping () -> Void,
        valueChanging: @escaping (T, ChangeMetadata) -> Void,
        valueDidChange: @escaping () -> Void)
    {
        self.init(onEvent: { event in
            switch event {
            case .beginPossibleAsyncChange:
                valueWillChange()
            case let .valueChanging(value, metadata):
                valueChanging(value, metadata)
            case .endPossibleAsyncChange:
                valueDidChange()
            }
        })
    }

    public func valueWillChange() {
        self.onEvent(.beginPossibleAsyncChange)
    }

    public func valueChanging(_ change: T, _ metadata: ChangeMetadata) {
        self.onEvent(.valueChanging(change, metadata))
    }

    public func valueChanging(_ change: T, transient: Bool = false) {
        self.valueChanging(change, ChangeMetadata(transient: transient))
    }
    
    public func valueDidChange() {
        self.onEvent(.endPossibleAsyncChange)
    }
    
    /// Shorthand for `valueWillChange`, `valueChanging` (transient=false), and `valueDidChange` in series.
    public func changed(_ value: T) {
        valueWillChange()
        valueChanging(value, transient: false)
        valueDidChange()
    }
}

public protocol SignalType: class {
    associatedtype Value
    
    /// Converts this instance into a concrete `Signal`.
    var signal: Signal<Value> { get }
    
    /// Registers the given observer, which will be notified when the signal delivers new values.
    func observe(_ observer: SignalObserver<Value>) -> ObserverRemoval
    
    /// Lifts this signal into an AsyncReadableProperty.
    func property() -> AsyncReadableProperty<Value>
    
    /// For testing purposes only.
    var observerCount: Int { get }
}

open class Signal<T>: SignalType {
    public typealias Value = T
    public typealias Observer = SignalObserver<T>
    public typealias Notify = SignalObserver<T>

    internal init() {
    }
    
    public static func pipe() -> (PipeSignal<T>, Notify) {
        let signal = PipeSignal<T>()
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
    
    open func property() -> AsyncReadableProperty<T> {
        return AsyncReadableProperty(signal: self)
    }

    /// Adds the given observer to the set of observers that are notified when this signal's value has changed.
    /// If the given observer is the first one to be added for this signal, the underlying signal source will
    /// be brought to action.  If the signal source has a value available, the given observer will have its
    /// `valueWillChange`, `valueChanging`, and `valueDidChange` handlers called before `observe` returns.
    public func observe(_ observer: Observer) -> ObserverRemoval {
        fatalError("Must be implemented by subclass")
    }

    /// Convenience form of `observe` that builds an Observer whose `valueWillChange` and `valueDidChange`
    /// handlers pass through to `notify`, but uses the given `valueChanging` handler.
    public func observe<U>(_ notify: SignalObserver<U>, _ valueChanging: @escaping (_ change: T, _ metadata: ChangeMetadata) -> Void) -> ObserverRemoval {
        return self.observe(SignalObserver(
            valueWillChange: notify.valueWillChange,
            valueChanging: valueChanging,
            valueDidChange: notify.valueDidChange
        ))
    }
    
    /// Convenience form of `observe` that builds an Observer whose `valueWillChange` and `valueDidChange`
    /// are no-ops, but uses the given `valueChanging` handler.
    public func observe(_ valueChanging: @escaping (_ change: T, _ metadata: ChangeMetadata) -> Void) -> ObserverRemoval {
        return self.observe(SignalObserver(
            valueWillChange: {},
            valueChanging: valueChanging,
            valueDidChange: {}
        ))
    }
    
    public var observerCount: Int {
        fatalError("Must be implemented by subclass")
    }
}

open class SourceSignal<T>: Signal<T> {
    
    private var observers: [UInt64: Observer] = [:]
    private var nextObserverID: UInt64 = 0
    
    internal override init() {
    }
    
    /// Should be overridden by subclasses to perform custom observe behavior (for example, starting the underlying
    /// signal source).
    internal func observeImpl(_ observer: Observer) {
        // TODO: Need to make this public if we eventually want to support arbitrary signal sources defined
        // outside this library
    }
    
    public override func observe(_ observer: Observer) -> ObserverRemoval {
        let id = nextObserverID
        nextObserverID += 1
        observers[id] = observer
        
        observeImpl(observer)
        
        return { self.observers.removeValue(forKey: id) }
    }
    
    internal func notifyWillChange() {
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
        for (_, observer) in observers {
            observer.valueDidChange()
        }
    }
    
    public override var observerCount: Int {
        return observers.count
    }
}

/// A SourceSignal that delivers a constant value when an observer is attached.
internal class ConstantSignal<T>: SourceSignal<T> {
    private let value: T
    
    init(_ value: T) {
        self.value = value
    }
    
    override func observeImpl(_ observer: Observer) {
        observer.valueChanging(value)
    }
}

/// A SourceSignal used in the implementation of `pipe`.  Allows for a function to be called
/// when an observer is attached.
public class PipeSignal<T>: SourceSignal<T> {
    public var onObserve: ((Observer) -> Void)?
    
    override func observeImpl(_ observer: Observer) {
        onObserve?(observer)
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
