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
    
    private var observed = false
    internal var mutableValue: T?
    public var value: T? {
        if !observed {
            // Note that `mutableValue` will be nil until either a) an observer is attached to `signal`
            // and it has delivered an initial value or b) someone tries to access `value` (in which case
            // we attach a dummy observer to kick the signal into action)
            let removal = signal.observe{ _ in }
            removal()
        }
        return mutableValue
    }
    
    public init(signal: Signal<T>) {
        self.mutableValue = nil
        self.underlyingSignal = signal

        let pipeSignal = PipeSignal<T>()
        self.signal = pipeSignal

        var changeCount = 0
        pipeSignal.onObserve = { [weak self] observer in
            guard let strongSelf = self else { return }
            strongSelf.observed = true
            if strongSelf.underlyingRemoval == nil {
                // Observe the underlying signal the first time someone observes our public signal
                strongSelf.underlyingRemoval = strongSelf.underlyingSignal.observe{ [weak self] event in
                    switch event {
                    case .beginPossibleAsyncChange:
                        changeCount += 1
                        pipeSignal.notifyBeginPossibleAsyncChange()
                        
                    case let .valueChanging(newValue, metadata):
                        self?.mutableValue = newValue
                        pipeSignal.notifyValueChanging(newValue, metadata)
                        
                    case .endPossibleAsyncChange:
                        changeCount -= 1
                        pipeSignal.notifyEndPossibleAsyncChange()
                    }
                }
            } else {
                // For subsequent observers, deliver our current value to just the observer being attached
                for _ in 0..<changeCount {
                    // If underlyingSignal is in an asynchronous change (delivered BeginPossibleAsync before
                    // this observer was attached), we need to give this new observer the corresponding
                    // number of BeginPossibleAsync notifications so that it is correctly balanced when the
                    // EndPossibleAsync notification(s) come in later
                    observer.notifyBeginPossibleAsyncChange()
                }
                if let value = strongSelf.mutableValue {
                    observer.notifyValueChanging(value)
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
}

private class ConstantValueAsyncProperty<T>: AsyncReadableProperty<T> {
    init(_ value: T) {
        super.init(signal: ConstantSignal(value))
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
        return AsyncReadableProperty(signal: self.signal)
    }
}
