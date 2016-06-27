//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

public struct ChangeMetadata {
    public let transient: Bool
    
    public init(transient: Bool) {
        self.transient = transient
    }
}

public enum ChangeResult<T> { case
    Change(T),
    NoChange
}

public class Binding {

    // XXX: Hang on to the owner of the signal, otherwise if no one else is
    // holding a strong reference to it, it may go away and the signal won't
    // deliver any changes
    // TODO: Find a better solution
    private var signalOwner: AnyObject?

    private var removal: (Void -> Void)?
    
    init(signalOwner: AnyObject, removal: Void -> Void) {
        self.signalOwner = signalOwner
        self.removal = removal
    }
    
    public func unbind() {
        signalOwner = nil
        removal?()
        removal = nil
    }
}

public protocol ReadablePropertyType: class {
    associatedtype Value
    
    var value: Value { get }
    var signal: Signal<Value> { get }
}

/// A concrete property that is readable and observable.
public class ReadableProperty<T>: ReadablePropertyType {
    public typealias Value = T
    
    public private(set) var value: T
    public let signal: Signal<T>
    private let notify: Signal<T>.Notify
    private let changing: (T, T) -> Bool
    
    public init(initialValue: T, signal: Signal<T>, notify: Signal<T>.Notify, changing: (T, T) -> Bool) {
        self.value = initialValue
        self.signal = signal
        self.notify = notify
        self.changing = changing
    }
    
    internal func setValue(newValue: T, _ metadata: ChangeMetadata) {
        if changing(value, newValue) {
            value = newValue
            notify(newValue: newValue, metadata: metadata)
        }
    }
}

/// A concrete property that can be updated when bound to another property.
public class BindableProperty<T> {

    public typealias Setter = (T, ChangeMetadata) -> Void

    // Note: This is exposed as `internal` only for easier access by tests.
    internal let set: Setter
    
    private var bindings: [UInt64: Binding] = [:]
    private var nextBindingID: UInt64 = 0

    internal init(set: Setter) {
        self.set = set
    }
    
    deinit {
        for (_, binding) in bindings {
            binding.unbind()
        }
    }

    /// Establishes a unidirectional binding between this property and the given signal.
    /// When the other property's value changes, this property's value will be updated.
    /// Note that calling `bind` will cause this property to take on the given initial
    /// value immediately.
    private func bind(signal: Signal<T>, initialValue: T?, owner: AnyObject) -> Binding {
        
        if let initialValue = initialValue {
            // Make this property take on the given initial value
            // TODO: Maybe only do this if this is the first thing being bound (i.e., when
            // the set of bindings is empty)
            // TODO: Does metadata have meaning here?
            self.set(initialValue, ChangeMetadata(transient: true))
        }
        
        // Observe the given signal for changes
        let signalObserverRemoval = signal.observe({ [weak self] value, metadata in
            guard let weakSelf = self else { return }
            weakSelf.set(value, metadata)
        })
        
        // Save and return the binding
        let bindingID = nextBindingID
        let binding = Binding(signalOwner: owner, removal: { [weak self] in
            signalObserverRemoval()
            self?.bindings.removeValueForKey(bindingID)?.unbind()
        })
        nextBindingID += 1
        bindings[bindingID] = binding
        return binding
    }
    
    /// Unbinds all existing bindings.
    public func unbindAll() {
        for (_, binding) in bindings {
            binding.unbind()
        }
        bindings.removeAll()
    }
}

public class WriteOnlyProperty<T>: BindableProperty<T> {
    
    public init(_ set: Setter) {
        super.init(set: set)
    }
}

public class ReadWriteProperty<T>: BindableProperty<T>, ReadablePropertyType {
    public typealias Value = T
    public typealias Getter = () -> T

    public var value: T {
        return get()
    }
    public let signal: Signal<T>
    
    private let get: Getter
    private let notify: Signal<T>.Notify
    
    internal init(get: Getter, set: Setter, signal: Signal<T>, notify: Signal<T>.Notify) {
        self.get = get
        self.signal = signal
        self.notify = notify
        super.init(set: set)
    }

    /// Establishes a bidirectional binding between this property and the given property.
    /// When this property's value changes, the other property's value will be updated and
    /// vice versa.  Note that calling `bindBidi` will cause this property to take on the
    /// other property's value immedately.
    public func bindBidi(other: ReadWriteProperty<T>) -> Binding {
        return connectBidi(
            other,
            initial: {
                self.set(other.get(), ChangeMetadata(transient: true))
            },
            forward: { .Change($0) },
            reverse: { .Change($0) }
        )
    }

    /// Establishes a bidirectional connection between this property and the given property,
    /// using `forward` and `reverse` to conditionally apply changes in each direction.
    /// Note that calling `connectBidi` will cause the other property to take on this
    /// property's value immediately (this is the opposite behavior from `bindBidi`).
    public func connectBidi<U>(other: ReadWriteProperty<U>, forward: T -> ChangeResult<U>, reverse: U -> ChangeResult<T>) -> Binding {
        return connectBidi(
            other,
            initial: {
                if case .Change(let initialValue) = forward(self.get()) {
                    other.set(initialValue, ChangeMetadata(transient: true))
                }
            },
            forward: forward,
            reverse: reverse
        )
    }

    private func connectBidi<U>(other: ReadWriteProperty<U>, initial: () -> Void, forward: T -> ChangeResult<U>, reverse: U -> ChangeResult<T>) -> Binding {
        var selfInitiatedChange = false
        
        // Observe the signal of the other property
        let signalObserverRemoval1 = other.signal.observe({ [weak self] value, metadata in
            if selfInitiatedChange { return }
            if case .Change(let newValue) = reverse(value) {
                selfInitiatedChange = true
                self?.set(newValue, metadata)
                selfInitiatedChange = false
            }
        })
        
        // Make the other property observe this property's signal
        let signalObserverRemoval2 = signal.observe({ [weak other] value, metadata in
            if selfInitiatedChange { return }
            if case .Change(let newValue) = forward(value) {
                selfInitiatedChange = true
                other?.set(newValue, metadata)
                selfInitiatedChange = false
            }
        })
        
        // Make this property take on the initial value from the other property (or vice versa)
        selfInitiatedChange = true
        initial()
        selfInitiatedChange = false
        
        // Save and return the binding
        let bindingID = nextBindingID
        let binding = Binding(signalOwner: other, removal: { [weak self] in
            signalObserverRemoval1()
            signalObserverRemoval2()
            self?.bindings.removeValueForKey(bindingID)?.unbind()
        })
        nextBindingID += 1
        bindings[bindingID] = binding
        return binding
    }
}

private class ConstantValueProperty<T>: ReadableProperty<T> {
    private init(_ value: T) {
        // TODO: Use a no-op signal here
        let (signal, notify) = Signal<T>.pipe()
        super.init(initialValue: value, signal: signal, notify: notify, changing: { _ in false })
    }
}

/// Returns a ValueProperty whose value never changes.  Note that since the value cannot change,
/// observers will never be notified of changes.
public func constantValueProperty<T>(value: T) -> ReadableProperty<T> {
    return ConstantValueProperty(value)
}

public class MutableValueProperty<T>: ReadWriteProperty<T> {
    
    public let change: (T, metadata: ChangeMetadata) -> Void
    
    private init(_ initialValue: T, valueChanging: (T, T) -> Bool, didSet: Setter?) {
        let (signal, notify) = Signal<T>.pipe()
        
        var value = initialValue
        
        change = { (newValue: T, metadata: ChangeMetadata) in
            if valueChanging(value, newValue) {
                value = newValue
                notify(newValue: newValue, metadata: metadata)
            }
        }
        
        super.init(
            get: {
                value
            },
            set: { newValue, metadata in
                if valueChanging(value, newValue) {
                    value = newValue
                    didSet?(newValue, metadata)
                    notify(newValue: newValue, metadata: metadata)
                }
            },
            signal: signal,
            notify: notify
        )
    }
    
    public func change(newValue: T, transient: Bool) {
        change(newValue, metadata: ChangeMetadata(transient: transient))
    }
}

public func mutableValueProperty<T>(initialValue: T, valueChanging: (T, T) -> Bool, _ didSet: BindableProperty<T>.Setter? = nil) -> MutableValueProperty<T> {
    return MutableValueProperty(initialValue, valueChanging: valueChanging, didSet: didSet)
}

public func mutableValueProperty<T: Equatable>(initialValue: T, _ didSet: BindableProperty<T>.Setter? = nil) -> MutableValueProperty<T> {
    return MutableValueProperty(initialValue, valueChanging: valueChanging, didSet: didSet)
}

public func mutableValueProperty<T: Equatable>(initialValue: T?, _ didSet: BindableProperty<T?>.Setter? = nil) -> MutableValueProperty<T?> {
    return MutableValueProperty(initialValue, valueChanging: valueChanging, didSet: didSet)
}

public class ExternalValueProperty<T>: ReadWriteProperty<T> {

    public let changed: (transient: Bool) -> Void

    public init(get: Getter, set: Setter) {
        let (signal, notify) = Signal<T>.pipe()

        changed = { (transient: Bool) in
            notify(newValue: get(), metadata: ChangeMetadata(transient: transient))
        }

        super.init(
            get: get,
            set: { newValue, metadata in
                set(newValue, metadata)
                notify(newValue: newValue, metadata: metadata)
            },
            signal: signal,
            notify: notify
        )
    }
}

public class ActionProperty: WriteOnlyProperty<()> {

    public init(_ action: () -> Void) {
        super.init({ _ in
            action()
        })
    }
}

// This syntax is borrowed from ReactiveCocoa.
infix operator <~ {
    associativity right
    precedence 93
}

public func <~ <T, RHS: ReadablePropertyType where RHS.Value == T>(lhs: BindableProperty<T>, rhs: RHS) -> Binding {
    return lhs.bind(rhs.signal, initialValue: rhs.value, owner: rhs)
}

// TODO: It seems that `~>` is defined somewhere already (not sure where exactly), so to avoid
// conflicts we use `~~>` here instead
infix operator ~~> {
    associativity right
    precedence 93
}

public func ~~> (lhs: Signal<()>, rhs: ActionProperty) -> Binding {
    // TODO: We invent an owner here; what if no one else owns the signal?
    return rhs.bind(lhs, initialValue: nil, owner: "")
}

infix operator <~> {
    associativity right
    precedence 93
}

public func <~> <T>(lhs: ReadWriteProperty<T>, rhs: ReadWriteProperty<T>) -> Binding {
    return lhs.bindBidi(rhs)
}

internal func valueChanging<T>(v0: T, v1: T) -> Bool {
    return true
}

internal func valueChanging<T: Equatable>(v0: T, v1: T) -> Bool {
    return v0 != v1
}

internal func valueChanging<T>(v0: T?, v1: T?) -> Bool {
    return true
}

internal func valueChanging<T: Equatable>(v0: T?, v1: T?) -> Bool {
    return v0 != v1
}
