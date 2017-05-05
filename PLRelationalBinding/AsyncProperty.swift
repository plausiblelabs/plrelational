//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

public protocol AsyncPropertyType {
    /// A convenience for putting the underlying source signal into action.  Normally that
    /// will occur the first time an observer begins observing this property's signal, but
    /// in some cases no observation is needed and the caller just wants this property to
    /// start delivering values.  This is a shorthand for `signal.observe` with a no-op observer.
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

extension AsyncReadablePropertyType {
    public func start() {
        _ = self.signal.observe({ _ in })
    }
}

/// A concrete readable property whose value is fetched asynchronously.
open class AsyncReadableProperty<T>: AsyncReadablePropertyType {
    public typealias Value = T
    public typealias SignalChange = T

    // Note that we observe our private `underlyingSignal` that was provided at init time, and then deliver `valueChanging` events
    // *after* we update our `value`.  This allows code to observe this property's public `signal` and be guaranteed that `value`
    // will contain the latest value before observers are notified.
    private let underlyingSignal: Signal<T>
    private var underlyingRemoval: ObserverRemoval?
    public let signal: Signal<T>
    
    public internal(set) var value: T?
    
    public init(initialValue: T?, signal: Signal<T>) {
        self.value = initialValue
        self.underlyingSignal = signal

        let pipeSignal = PipeSignal<T>()
        self.signal = pipeSignal

        var changeCount = 0
        pipeSignal.onObserve = { observer in
            if self.underlyingRemoval == nil {
                // Observe the underlying signal the first time someone observes our public signal
                guard self.underlyingRemoval == nil else { return }
                self.underlyingRemoval = self.underlyingSignal.observe(SignalObserver(
                    valueWillChange: {
                        changeCount += 1
                        pipeSignal.notifyWillChange()
                    },
                    valueChanging: { [weak self] newValue, metadata in
                        self?.value = newValue
                        pipeSignal.notifyChanging(newValue, metadata: metadata)
                    },
                    valueDidChange: {
                        changeCount -= 1
                        pipeSignal.notifyDidChange()
                    }
                ))
            } else {
                // For subsequent observers, deliver our current value to just the observer being attached
                for _ in 0..<changeCount {
                    // If underlyingSignal is in an asynchronous change (delivered WillChange before
                    // this observer was attached), we need to give this new observer the corresponding
                    // number of WillChange notifications so that it is correctly balanced when the
                    // DidChange notification(s) come in later
                    observer.valueWillChange()
                }
                if let value = self.value {
                    observer.valueWillChange()
                    observer.valueChanging(value)
                    observer.valueDidChange()
                }
            }
        }
    }
    
    deinit {
        underlyingRemoval?()
    }
    
    public var property: AsyncReadableProperty<T> {
        return self
    }
    
    public static func pipe(initialValue: T? = nil) -> (AsyncReadableProperty<T>, Signal<T>.Notify) {
        let (signal, notify) = Signal<T>.pipe()
        let property = AsyncReadableProperty(initialValue: initialValue, signal: signal)
        return (property, notify)
    }
}

private class ConstantValueAsyncProperty<T>: AsyncReadableProperty<T> {
    init(_ value: T) {
        super.init(initialValue: value, signal: ConstantSignal(value))
    }
}

/// Returns an AsyncReadableProperty whose value never changes.
public func constantValueAsyncProperty<T>(_ value: T) -> AsyncReadableProperty<T> {
    return ConstantValueAsyncProperty(value)
}

/// A concrete readable property whose value can be updated and fetched asynchronously.
open class AsyncReadWriteProperty<T>: AsyncReadableProperty<T> {

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

extension ReadablePropertyType {
    /// Returns an AsyncReadableProperty that is derived from this synchronous property's signal.
    public func async() -> AsyncReadableProperty<Value> {
        return AsyncReadableProperty(initialValue: self.value, signal: self.signal)
    }
}
