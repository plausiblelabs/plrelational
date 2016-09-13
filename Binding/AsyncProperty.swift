//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

public protocol AsyncReadablePropertyType: class {
    associatedtype Value
    associatedtype SignalChange
    
    var value: Value? { get }
    var signal: Signal<SignalChange> { get }
    
    func start()
}

/// A concrete readable property whose value is fetched asynchronously.
open class AsyncReadableProperty<T>: AsyncReadablePropertyType {
    public typealias Value = T
    public typealias SignalChange = T
    
    open internal(set) var value: T?
    open let signal: Signal<T>
    fileprivate var removal: ObserverRemoval!
    fileprivate var started = false
    
    public init(_ signal: Signal<T>) {
        self.signal = signal
        self.removal = signal.observe({ [weak self] newValue, _ in
            self?.value = newValue
        })
    }
    
    open func start() {
        // TODO: Need to make a SignalProducer like thing that can create a unique signal
        // each time start() is called; for now we'll assume it can be called only once
        if !started {
            signal.start()
            started = true
        }
    }
    
    deinit {
        removal()
    }
}

/// A concrete readable property whose value can be updated and fetched asynchronously.
open class AsyncReadWriteProperty<T>: AsyncReadablePropertyType {
    public typealias Value = T
    public typealias SignalChange = T

    open var value: T? {
        return getValue()
    }
    
    open let signal: Signal<T>
    fileprivate var started = false

    internal init(signal: Signal<T>) {
        self.signal = signal
    }
    
    open func start() {
        // TODO: For now we'll assume it can be called only once
        if !started {
            signal.start()
            started = true
        }
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
