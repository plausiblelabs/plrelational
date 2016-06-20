//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

public class Property<T> {

    public typealias Setter = (T, ChangeMetadata) -> Void
    
    private let set: Setter
    private var removal: ObserverRemoval?
    private var owner: AnyObject?
    
    public init(_ set: Setter) {
        self.set = set
    }

    deinit {
        removal?()
    }
    
    private func bind(signal: Signal<T>, initialValue: T, owner: AnyObject) {
        // Unbind if already bound to something
        unbind()
        
        // Make this property take on the given initial value
        // TODO: Does metadata have meaning here?
        self.set(initialValue, ChangeMetadata(transient: true))
        
        // Observe the given signal for changes
        self.removal = signal.observe({ [weak self] value, metadata in
            guard let weakSelf = self else { return }
            weakSelf.set(value, metadata)
        })
        
        // XXX: Hang on to the owner of the signal, otherwise if no one else is
        // holding a strong reference to it, it may go away and the signal won't
        // deliver any changes
        // TODO: Find a better solution
        self.owner = owner
    }
    
    public func unbind() {
        removal?()
        removal = nil
        owner = nil
    }
}

public class ReadableProperty<T>: Property<T> {

    public typealias Getter = () -> T
    
    public let get: Getter
    
    public init(get: Getter, set: Setter) {
        self.get = get
        super.init(set)
    }
}

public class ObservableProperty<T>: ReadableProperty<T> {

    public let signal: Signal<T>
    
    public init(get: Getter, set: Setter, signal: Signal<T>) {
        self.signal = signal
        super.init(get: get, set: set)
    }
}

public class BidiProperty<T>: ObservableProperty<T> {

    private var otherRemoval: ObserverRemoval?
    
    public override init(get: Getter, set: Setter, signal: Signal<T>) {
        super.init(get: get, set: set, signal: signal)
    }

    deinit {
        otherRemoval?()
    }

    public func bindBidi(other: BidiProperty<T>) {
        // Unbind if already bound to something
        unbind()

        // Make this property initially take on the current value of the other property
        self.set(other.get(), ChangeMetadata(transient: true))
        
        // Observe the signal of the other property
        self.removal = other.signal.observe({ [weak self] value, metadata in
            guard let weakSelf = self else { return }
            weakSelf.set(value, metadata)
        })
        
        // Make the other property observe this property's signal
        self.otherRemoval = signal.observe({ value, metadata in
            other.set(value, metadata)
        })
    }

    public override func unbind() {
        super.unbind()
        
        otherRemoval?()
        otherRemoval = nil
    }
}
    
public class MutableBidiProperty<T>: BidiProperty<T> {

    public let changed: (transient: Bool) -> Void
    
    public init(get: Getter, set: Setter) {
        let signal: Signal<T>
        let notify: Signal<T>.Notify
        (signal, notify) = Signal.pipe()
        
        changed = { (transient: Bool) in
            notify(newValue: get(), metadata: ChangeMetadata(transient: transient))
        }
        
        super.init(get: get, set: set, signal: signal)
    }
}

public class ValueBidiProperty<T>: BidiProperty<T> {

    public let change: (newValue: T, transient: Bool) -> Void
    
    public init(initialValue: T, didSet: Setter? = nil) {
        let signal: Signal<T>
        let notify: Signal<T>.Notify
        (signal, notify) = Signal.pipe()
        
        var value = initialValue

        change = { (newValue: T, transient: Bool) in
            value = newValue
            notify(newValue: newValue, metadata: ChangeMetadata(transient: transient))
        }
        
        super.init(
            get: {
                value
            },
            set: { newValue, metadata in
                value = newValue
                didSet?(newValue, metadata)
            },
            signal: signal
        )
    }
}

// This syntax is borrowed from ReactiveCocoa.
infix operator <~ {
    associativity right
    precedence 93
}

public func <~ <T>(lhs: Property<T>, rhs: ObservableValue<T>?) {
    if let rhs = rhs {
        lhs.bind(rhs.signal, initialValue: rhs.value, owner: rhs)
    } else {
        lhs.unbind()
    }
}

public func <~ <T>(lhs: Property<T>, rhs: ObservableProperty<T>?) {
    if let rhs = rhs {
        lhs.bind(rhs.signal, initialValue: rhs.get(), owner: rhs)
    } else {
        lhs.unbind()
    }
}

infix operator <~> {
    associativity right
    precedence 93
}

public func <~> <T>(lhs: BidiProperty<T>, rhs: BidiProperty<T>?) {
    if let rhs = rhs {
        lhs.bindBidi(rhs)
    } else {
        lhs.unbind()
    }
}
