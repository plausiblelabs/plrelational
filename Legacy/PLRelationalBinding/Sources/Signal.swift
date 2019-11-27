//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

public typealias ObserverRemoval = () -> Void

/// Describes a change that is delivered on a signal.
public struct ChangeMetadata {
    
    /// Whether this change is transient (a fleeting change such as fast keystrokes) or one that is considered
    /// more significant (a change that should be committed to a backing store).
    public let transient: Bool

    /// Initializes the metadata with the given transient flag.
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
    /// Indicates that a new value *may* be forthcoming.
    case beginPossibleAsyncChange
    
    /// Indicates that the signal's value is changing.
    case valueChanging(T, ChangeMetadata)
    
    /// Indicates that a new value *may* have been delivered asynchronously.
    case endPossibleAsyncChange
}

/// An observer that responds to events delivered by a Signal.
public struct SignalObserver<T> {
    
    /// The event callback function.
    public let onEvent: (SignalEvent<T>) -> Void

    /// Initializes the observer with a callback function.
    public init(onEvent: @escaping (SignalEvent<T>) -> Void) {
        self.onEvent = onEvent
    }

    /// Invokes `onEvent` with a `.beginPossibleAsyncChange` event.
    public func notifyBeginPossibleAsyncChange() {
        self.onEvent(.beginPossibleAsyncChange)
    }
    
    /// Invokes `onEvent` with a `.valueChanging` event.
    public func notifyValueChanging(_ change: T, _ metadata: ChangeMetadata) {
        self.onEvent(.valueChanging(change, metadata))
    }

    /// Invokes `onEvent` with a `.valueChanging` event.
    public func notifyValueChanging(_ change: T, transient: Bool = false) {
        self.notifyValueChanging(change, ChangeMetadata(transient: transient))
    }
    
    /// Invokes `onEvent` with an `.endPossibleAsyncChange` event.
    public func notifyEndPossibleAsyncChange() {
        self.onEvent(.endPossibleAsyncChange)
    }
}

/// Base protocol for signals, which deliver values produced by some source and notify observers when a change
/// is being made.
public protocol SignalType: class {
    /// The type of values that are delivered on this signal.
    associatedtype Value
    
    /// Converts this instance into a concrete `Signal`.
    var signal: Signal<Value> { get }
    
    /// Adds the given observer to the set of observers that are notified when this signal's value has changed.
    /// If the given observer is the first one to be added for this signal, the underlying signal source will
    /// be brought to action.  If the signal source has a value available, the given observer will be sent a
    /// `valueChanging` event before `observe` returns.
    func addObserver(_ observer: SignalObserver<Value>) -> ObserverRemoval
    
    /// Lifts this signal into an AsyncReadableProperty.
    func property() -> AsyncReadableProperty<Value>
    
    /// Returns the number of attached observers.  For testing purposes only.
    var observerCount: Int { get }
}

extension SignalType {
    
    // MARK: Observation
    
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

/// Base (abstract) implementation of the `SignalType` protocol.
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
    
    public override init() {
    }
    
    /// Should be overridden by subclasses to perform custom observe behavior (for example, starting the underlying
    /// signal source).
    internal func addObserverImpl(_ observer: Observer) {
        // TODO: Need to make this open if we eventually want to support arbitrary signal sources defined
        // outside this library
    }
    
    /// Called when the last observer has been removed.
    internal func onEmptyObserverSet() {
        // TODO: Need to make this open if we eventually want to support arbitrary signal sources defined
        // outside this library
    }
    
    public override func addObserver(_ observer: Observer) -> ObserverRemoval {
        let id = nextObserverID
        nextObserverID += 1
        observers[id] = observer
        
        addObserverImpl(observer)
        
        return { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.observers.removeValue(forKey: id)
            if strongSelf.observers.isEmpty {
                strongSelf.onEmptyObserverSet()
            }
        }
    }
    
    /// Delivers a `.beginPossibleAsyncChange` event to all observers of this signal.
    public func notifyBeginPossibleAsyncChange() {
        for (_, observer) in observers {
            observer.notifyBeginPossibleAsyncChange()
        }
    }
    
    /// Delivers a `.valueChanging` event to all observers of this signal.
    public func notifyValueChanging(_ change: T, _ metadata: ChangeMetadata) {
        for (_, observer) in observers {
            observer.notifyValueChanging(change, metadata)
        }
    }
    
    /// Delivers a `.valueChanging` event to all observers of this signal.
    public func notifyValueChanging(_ change: T, transient: Bool = false) {
        for (_, observer) in observers {
            observer.notifyValueChanging(change, transient: transient)
        }
    }
    
    /// Delivers an `.endPossibleAsyncChange` event to all observers of this signal.
    public func notifyEndPossibleAsyncChange() {
        for (_, observer) in observers {
            observer.notifyEndPossibleAsyncChange()
        }
    }
    
    public override var observerCount: Int {
        return observers.count
    }
}

extension SourceSignal where T == () {
    /// Shorthand for delivering an empty `.valueChanging` event to all observers of this signal.
    public func notifyAction() {
        self.notifyValueChanging(())
    }
}

/// A SourceSignal that delivers a constant value when an observer is attached.
internal class ConstantSignal<T>: SourceSignal<T> {
    private let value: T
    
    init(_ value: T) {
        self.value = value
    }
    
    override func addObserverImpl(_ observer: Observer) {
        observer.notifyValueChanging(value)
    }
}

/// A SourceSignal that allows for a function to be called when an observer is attached.
public class PipeSignal<T>: SourceSignal<T> {
    
    /// The function that is called when an observer is attached.
    public var onObserve: ((Observer) -> Void)?
    
    override func addObserverImpl(_ observer: Observer) {
        onObserve?(observer)
    }
}

// XXX: Workaround for cases where we want to have a Signal that mutates `self` but need
// a signal to pass to `super.init`.  The `underlyingSignal` must be set before an
// observer is attached.
internal class DelegatingSignal<T>: Signal<T> {
    
    var underlyingSignal: Signal<T>!
    
    override func addObserver(_ observer: Observer) -> ObserverRemoval {
        return underlyingSignal.addObserver(observer)
    }
    
    override var observerCount: Int {
        return underlyingSignal.observerCount
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
