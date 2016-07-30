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
public class AsyncReadableProperty<T>: AsyncReadablePropertyType {
    public typealias Value = T
    public typealias SignalChange = T
    
    public internal(set) var value: T?
    public let signal: Signal<T>
    private var removal: ObserverRemoval!
    private var started = false
    
    public init(_ signal: Signal<T>) {
        self.signal = signal
        self.removal = signal.observe({ [weak self] newValue, _ in
            self?.value = newValue
        })
    }
    
    public func start() {
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
public class AsyncReadWriteProperty<T>: AsyncReadablePropertyType {
    public typealias Value = T
    public typealias SignalChange = T

    public typealias Getter = () -> T?
    public typealias Setter = (T, ChangeMetadata) -> Void

    public var value: T? {
        return get()
    }
    
    private let get: Getter
    // Note: This is exposed as `internal` only for easier access by tests.
    internal let set: Setter

    public let signal: Signal<T>
    private var started = false

    internal init(get: Getter, set: Setter, signal: Signal<T>) {
        self.get = get
        self.set = set
        self.signal = signal
    }
    
    public func start() {
        // TODO: For now we'll assume it can be called only once
        if !started {
            signal.start()
            started = true
        }
    }
}
