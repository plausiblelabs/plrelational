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
    
    public func notifyBeginPossibleAsyncChange() {
        self.onEvent(.beginPossibleAsyncChange)
    }
    
    public func notifyValueChanging(_ change: T, _ metadata: ChangeMetadata) {
        self.onEvent(.valueChanging(change, metadata))
    }

    public func notifyValueChanging(_ change: T, transient: Bool = false) {
        self.notifyValueChanging(change, ChangeMetadata(transient: transient))
    }
    
    public func notifyEndPossibleAsyncChange() {
        self.onEvent(.endPossibleAsyncChange)
    }
}

public protocol SignalType: class {
    associatedtype Value
    
    /// Converts this instance into a concrete `Signal`.
    var signal: Signal<Value> { get }
    
    /// Registers the given observer, which will be notified when the signal delivers new values.
    func addObserver(_ observer: SignalObserver<Value>) -> ObserverRemoval
    
    /// Lifts this signal into an AsyncReadableProperty.
    func property() -> AsyncReadableProperty<Value>
    
    /// For testing purposes only.
    var observerCount: Int { get }
}

extension SignalType {
    
    /// Convenience form of observe that takes an event handler function.
    public func observe(_ onEvent: @escaping (SignalEvent<Value>) -> Void) -> ObserverRemoval {
        return self.addObserver(SignalObserver<Value>(onEvent: onEvent))
    }

    /// Convenience form of observe that only responds to `valueChanging` events.  Any other events are treated as no-ops.
    public func observeValueChanging(_ onValueChanging: @escaping (Value, ChangeMetadata) -> Void) -> ObserverRemoval {
        return self.observe{ event in
            switch event {
            case let .valueChanging(value, metadata):
                onValueChanging(value, metadata)
            case .beginPossibleAsyncChange, .endPossibleAsyncChange:
                break
            }
        }
    }

    /// Convenience form of observe that only accepts `valueChanging` events.  Any other events are considered
    /// a fatal error.  This is mainly useful in cases where the observed signal is expected to be fully synchronous,
    /// i.e., always delivers changes immediately.
    public func observeSynchronousValueChanging(_ onValueChanging: @escaping (Value, ChangeMetadata) -> Void) -> ObserverRemoval {
        return self.observe{ event in
            switch event {
            case .beginPossibleAsyncChange, .endPossibleAsyncChange:
                fatalError("Asynchronous events not allowed")
            case let .valueChanging(value, metadata):
                onValueChanging(value, metadata)
            }
        }
    }
}

open class Signal<T>: SignalType {
    public typealias Value = T
    public typealias Observer = SignalObserver<T>

    internal init() {
    }
    
    public var signal: Signal<T> {
        return self
    }
    
    open func property() -> AsyncReadableProperty<T> {
        return AsyncReadableProperty(signal: self)
    }

    /// Adds the given observer to the set of observers that are notified when this signal's value has changed.
    /// If the given observer is the first one to be added for this signal, the underlying signal source will
    /// be brought to action.  If the signal source has a value available, the given observer will be sent a
    /// `valueChanging` event before `observe` returns.
    public func addObserver(_ observer: Observer) -> ObserverRemoval {
        fatalError("Must be implemented by subclass")
    }
    
    public var observerCount: Int {
        fatalError("Must be implemented by subclass")
    }
}

/// A signal that exposes methods for notifying observers.
open class SourceSignal<T>: Signal<T> {
    
    fileprivate var observers: [UInt64: Observer] = [:]
    private var nextObserverID: UInt64 = 0
    
    internal override init() {
    }
    
    /// Should be overridden by subclasses to perform custom observe behavior (for example, starting the underlying
    /// signal source).
    internal func observeImpl(_ observer: Observer) {
        // TODO: Need to make this public if we eventually want to support arbitrary signal sources defined
        // outside this library
    }
    
    public override func addObserver(_ observer: Observer) -> ObserverRemoval {
        let id = nextObserverID
        nextObserverID += 1
        observers[id] = observer
        
        observeImpl(observer)
        
        return { self.observers.removeValue(forKey: id) }
    }
    
    public func notifyBeginPossibleAsyncChange() {
        for (_, observer) in observers {
            observer.notifyBeginPossibleAsyncChange()
        }
    }
    
    public func notifyValueChanging(_ change: T, _ metadata: ChangeMetadata) {
        for (_, observer) in observers {
            observer.notifyValueChanging(change, metadata)
        }
    }
    
    public func notifyValueChanging(_ change: T, transient: Bool = false) {
        for (_, observer) in observers {
            observer.notifyValueChanging(change, transient: transient)
        }
    }
    
    public func notifyEndPossibleAsyncChange() {
        for (_, observer) in observers {
            observer.notifyEndPossibleAsyncChange()
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
        observer.notifyValueChanging(value)
    }
}

/// A SourceSignal that allows for a function to be called when an observer is attached.
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
