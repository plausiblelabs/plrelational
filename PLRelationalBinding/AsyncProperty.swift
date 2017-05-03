//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

public protocol AsyncPropertyType {
    /// Causes the underlying signal to start delivering values.
    func start()
}

public protocol AsyncReadablePropertyType: class, AsyncPropertyType {
    associatedtype Value
    associatedtype SignalChange

    /// Converts this instance into a concrete `AsyncReadableProperty`.
    var property: AsyncReadableProperty<Value> { get }

    /// The underlying signal.
    var signal: Signal<SignalChange> { get }
    
    /// The most recent value delivered by the underlying signal.
    var value: Value? { get }
}

/// A concrete readable property whose value is fetched asynchronously.
open class AsyncReadableProperty<T>: AsyncReadablePropertyType {
    public typealias Value = T
    public typealias SignalChange = T

    // Note that we observe our private `underlyingSignal` that was provided at init time, and then deliver `valueChanging` events
    // *after* we update our `value`.  This allows code to observe this property's public `signal` and be guaranteed that `value`
    // will contain the latest value before observers are notified.
    private let underlyingSignal: Signal<T>
    public let signal: Signal<T>
    private let notify: Signal<T>.Notify
    
    public internal(set) var value: T?
    private var removal: ObserverRemoval?
    private var started = false
    
    public init(initialValue: T?, signal: Signal<T>) {
        self.value = initialValue
        self.underlyingSignal = signal
        (self.signal, self.notify) = Signal.pipe()
    }
    
    deinit {
        removal?()
    }
    
    public var property: AsyncReadableProperty<T> {
        return self
    }
    
    public func start() {
        // TODO: Need to make a SignalProducer like thing that can create a unique signal
        // each time start() is called; for now we'll assume it can be called only once
        if !started {
            // Observe the underlying signal
            let deliverInitial = value == nil
            removal = underlyingSignal.observe(SignalObserver(
                valueWillChange: { [weak self] in
                    self?.notify.valueWillChange()
                },
                valueChanging: { [weak self] newValue, metadata in
                    self?.value = newValue
                    self?.notify.valueChanging(newValue, metadata)
                },
                valueDidChange: { [weak self] in
                    self?.notify.valueDidChange()
                }
            ))
            
            // The following isn't strictly needed, but just for clarity we'll start our public signal before starting
            // the underlying signal (which is required)
            signal.start(deliverInitial: false)
            
            // Start the underlying signal
            underlyingSignal.start(deliverInitial: deliverInitial)
            
            // Take on underlying signal's change count
            signal.setChangeCount(underlyingSignal.changeCount)

            started = true
        }
    }
    
    public static func pipe(initialValue: T? = nil) -> (AsyncReadableProperty<T>, Signal<T>.Notify) {
        let (signal, notify) = Signal<T>.pipe()
        let property = AsyncReadableProperty(initialValue: initialValue, signal: signal)
        return (property, notify)
    }
}

private class ConstantValueAsyncProperty<T>: AsyncReadableProperty<T> {
    init(_ value: T) {
        // TODO: Use a no-op signal here
        let (signal, _) = Signal<T>.pipe()
        super.init(initialValue: value, signal: signal)
    }
}

/// Returns an AsyncReadableProperty whose value never changes.  Note that since the value cannot change,
/// observers will never be notified of changes.
public func constantValueAsyncProperty<T>(_ value: T) -> AsyncReadableProperty<T> {
    return ConstantValueAsyncProperty(value)
}


/// A concrete readable property whose value can be updated and fetched asynchronously.
open class AsyncReadWriteProperty<T>: AsyncReadablePropertyType {
    public typealias Value = T
    public typealias SignalChange = T

    public var value: T? {
        return getValue()
    }
    
    // TODO: Need to rework this to be more like AsyncReadableProperty, which now has a private `underlyingSignal` and a separate public `signal`
    public let signal: Signal<T>
    private var started = false

    internal init(signal: Signal<T>) {
        self.signal = signal
    }
    
    public var property: AsyncReadableProperty<T> {
        return AsyncReadableProperty(initialValue: self.value, signal: self.signal)
    }
    
    public func start() {
        // TODO: For now we'll assume it can be called only once
        if !started {
            startImpl()
            started = true
        }
    }
    
    /// Invokes the provided startFunc by default, but subclasses can override for custom start behavior.
    internal func startImpl() {
        fatalError("Must be implemented by subclasses")
    }
    
    /// Returns the current value.  This must be overridden by subclasses and is intended to be
    /// called by the `bind` implementations only, not by external callers.
    internal func getValue() -> T? {
        fatalError("Must be implemented by subclasses")
    }
    
    /// Sets the new value.  This must be overridden by subclasses and is intended to be
    /// called by the `bind` implementations only, not by external callers.
    internal func setValue(_ value: T, _ metadata: ChangeMetadata) {
        fatalError("Must be implemented by subclasses")
    }
}

extension SignalType {
    /// Lifts this signal into an AsyncReadableProperty.
    public func property() -> AsyncReadableProperty<Self.Value> {
        return AsyncReadableProperty(initialValue: nil, signal: self.signal)
    }
}

extension ReadablePropertyType where Value == SignalChange {
    /// Returns an AsyncReadableProperty that is derived from this synchronous property's signal.
    public func async() -> AsyncReadableProperty<Value> {
        return AsyncReadableProperty(initialValue: self.value, signal: self.signal)
    }
}
