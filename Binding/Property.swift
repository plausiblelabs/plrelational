//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

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
    associatedtype SignalChange = Value
    
    var value: Value { get }
    var signal: Signal<SignalChange> { get }
}

/// A concrete property that is readable and observable.
public class ReadableProperty<T>: ReadablePropertyType {
    public typealias Value = T
    public typealias Change = T
    
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
            notify.valueChanging(change: newValue, metadata: metadata)
        }
    }
}

/// A concrete property that can be updated when bound to another property.
public class BindableProperty<T> {
    public typealias Setter = (T, ChangeMetadata) -> Void

    private let changeHandler: ChangeHandler
    
    private var bindings: [UInt64: Binding] = [:]
    private var nextBindingID: UInt64 = 0

    internal init(changeHandler: ChangeHandler) {
        self.changeHandler = changeHandler
    }
    
    deinit {
        for (_, binding) in bindings {
            binding.unbind()
        }
    }

    /// Sets the new value.  This must be overridden by subclasses and is intended to be
    /// called by the `bind` implementations only, not by external callers.
    internal func setValue(newValue: T, _ metadata: ChangeMetadata) {
        fatalError("Must be implemented by subclasses")
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
            self.setValue(initialValue, ChangeMetadata(transient: true))
        }
        
        // Take on the given signal's change count
        changeHandler.incrementCount(signal.changeCount)
        
        // Observe the given signal for changes
        let signalObserverRemoval = signal.observe(SignalObserver(
            valueWillChange: { [weak self] in
                self?.changeHandler.willChange()
            },
            valueChanging: { [weak self] value, metadata in
                guard let weakSelf = self else { return }
                weakSelf.setValue(value, metadata)
            },
            valueDidChange: { [weak self] in
                self?.changeHandler.didChange()
            }
        ))
        
        // Save and return the binding
        let bindingID = nextBindingID
        let binding = Binding(signalOwner: owner, removal: { [weak self, weak signal] in
            signalObserverRemoval()
            if let strongSelf = self {
                if let binding = strongSelf.bindings.removeValueForKey(bindingID) {
                    binding.unbind()
                }
                if let signal = signal {
                    strongSelf.changeHandler.decrementCount(signal.changeCount)
                }
            }
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

    private let set: Setter
    
    // TODO: Drop the default value (to make sure all clients are properly migrated to the new system)
    public init(set: Setter, changeHandler: ChangeHandler = ChangeHandler()) {
        self.set = set
        super.init(changeHandler: changeHandler)
    }
    
    override internal func setValue(newValue: T, _ metadata: ChangeMetadata) {
        set(newValue, metadata)
    }
}

public class ReadWriteProperty<T>: BindableProperty<T>, ReadablePropertyType {
    public typealias Value = T

    public var value: T {
        return getValue()
    }
    public let signal: Signal<T>
    private let notify: Signal<T>.Notify
    
    private var selfInitiatedChangeCount = 0
    
    internal init(signal: Signal<T>, notify: Signal<T>.Notify, changeHandler: ChangeHandler) {
        self.signal = signal
        self.notify = notify
        super.init(changeHandler: changeHandler)
    }

    /// Returns the current value.  This must be overridden by subclasses and is intended to be
    /// called by the `bind` implementations only, not by external callers.
    internal func getValue() -> T {
        fatalError("Must be implemented by subclasses")
    }
    
    /// Establishes a bidirectional binding between this property and the given property.
    /// When this property's value changes, the other property's value will be updated and
    /// vice versa.  Note that calling `bindBidi` will cause this property to take on the
    /// other property's value immedately.
    public func bindBidi(other: ReadWriteProperty<T>) -> Binding {
        return connectBidi(
            other,
            initial: {
                self.setValue(other.value, ChangeMetadata(transient: true))
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
                if case .Change(let initialValue) = forward(self.value) {
                    other.setValue(initialValue, ChangeMetadata(transient: true))
                }
            },
            forward: forward,
            reverse: reverse
        )
    }

    private func connectBidi<U>(other: ReadWriteProperty<U>, initial: () -> Void, forward: T -> ChangeResult<U>, reverse: U -> ChangeResult<T>) -> Binding {
        var selfInitiatedChange = false
        
        // Observe the signal of the other property
        let signalObserverRemoval1 = other.signal.observe(SignalObserver(
            // TODO: How to deal with ChangeHandler here?
            valueWillChange: {},
            valueChanging: { [weak self] value, metadata in
                if selfInitiatedChange { return }
                if case .Change(let newValue) = reverse(value) {
                    selfInitiatedChange = true
                    self?.setValue(newValue, metadata)
                    selfInitiatedChange = false
                }
            },
            // TODO: How to deal with ChangeHandler here?
            valueDidChange: {}
        ))
        
        // Make the other property observe this property's signal
        let signalObserverRemoval2 = signal.observe(SignalObserver(
            // TODO: How to deal with ChangeHandler here?
            valueWillChange: {},
            valueChanging: { [weak other] value, metadata in
                if selfInitiatedChange { return }
                if case .Change(let newValue) = forward(value) {
                    selfInitiatedChange = true
                    other?.setValue(newValue, metadata)
                    selfInitiatedChange = false
                }
            },
            // TODO: How to deal with ChangeHandler here?
            valueDidChange: {}
        ))
        
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
    
    /// Establishes a bidirectional binding between this property and the given property.
    /// When this property's value changes, the other property's value will be updated and
    /// vice versa.  Note that calling `bindBidi` will cause this property to take on the
    /// other property's value immedately (if the value is defined).
    public func bindBidi(other: AsyncReadWriteProperty<T>) -> Binding {
        return connectBidi(
            other,
            initial: {
                if let otherValue = other.value {
                    self.setValue(otherValue, ChangeMetadata(transient: true))
                }
            },
            forward: { .Change($0) },
            reverse: { .Change($0) }
        )
    }
    
    private func connectBidi<U>(other: AsyncReadWriteProperty<U>, initial: () -> Void, forward: T -> ChangeResult<U>, reverse: U -> ChangeResult<T>) -> Binding {
        // Observe the signal of the other property
        let signalObserverRemoval1 = other.signal.observe(SignalObserver(
            valueWillChange: { [weak self] in
                guard let strongSelf = self else { return }
                print("OTHER SIGNAL VALUE WILL CHANGE: \(strongSelf.selfInitiatedChangeCount)")
                if strongSelf.selfInitiatedChangeCount > 0 { return }
                strongSelf.changeHandler.willChange()
            },
            valueChanging: { [weak self] value, metadata in
                guard let strongSelf = self else { return }
                //if selfInitiatedChange { return }
                print("OTHER SIGNAL VALUE CHANGING: \(strongSelf.selfInitiatedChangeCount)")
                if strongSelf.selfInitiatedChangeCount > 0 { return }
                if case .Change(let newValue) = reverse(value) {
                    self?.setValue(newValue, metadata)
                }
            },
            valueDidChange: { [weak self] in
                guard let strongSelf = self else { return }
                print("OTHER SIGNAL VALUE DID CHANGE: \(strongSelf.selfInitiatedChangeCount)")
                if strongSelf.selfInitiatedChangeCount > 0 { return }
                strongSelf.changeHandler.didChange()
            }
        ))
        
        // Make the other property observe this property's signal
        let signalObserverRemoval2 = signal.observe(SignalObserver(
            // TODO: valueWill/DidChange are no-ops here; we don't touch the change handler
            // because this is a self-initiated change, and we don't want to disable the associated
            // control while the user is editing the value; all of this needs to be reconsidered
            valueWillChange: {
                print("SELF SIGNAL VALUE WILL CHANGE: \(self.selfInitiatedChangeCount)")
            },
            valueChanging: { [weak self, weak other] value, metadata in
                guard let strongSelf = self else { return }
                if strongSelf.selfInitiatedChangeCount > 0 { return }
                print("SELF SIGNAL VALUE CHANGING: \(strongSelf.selfInitiatedChangeCount)")
                if case .Change(let newValue) = forward(value) {
                    other?.setValue(newValue, metadata)
                }
            },
            valueDidChange: {
                print("SELF SIGNAL VALUE DID CHANGE: \(self.selfInitiatedChangeCount)")
            }
        ))
        
        // Make this property take on the initial value from the other property (or vice versa)
        initial()
        
        // Take on the given signal's change count
        changeHandler.incrementCount(other.signal.changeCount)

        // Start the other property's signal
        print("STARTING OTHER SIGNAL")
        other.start()
        print("STARTED OTHER SIGNAL")
        
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

    private let valueChanging: (T, T) -> Bool
    private let didSet: Setter?
    private var mutableValue: T
    
    private init(_ initialValue: T, changeHandler: ChangeHandler, valueChanging: (T, T) -> Bool, didSet: Setter?) {
        self.valueChanging = valueChanging
        self.didSet = didSet
        self.mutableValue = initialValue

        let (signal, notify) = Signal<T>.pipe()
        super.init(
            signal: signal,
            notify: notify,
            changeHandler: changeHandler
        )
    }
    
    /// Called to update the underlying value and notify observers that the value has been changed.
    public func change(newValue: T, transient: Bool) {
        change(newValue, metadata: ChangeMetadata(transient: transient))
    }
    
    /// Called to update the underlying value and notify observers that the value has been changed.
    public func change(newValue: T, metadata: ChangeMetadata) {
        print("MUTABLE VALUE CHANGE MAYBE: \(newValue)")
        if valueChanging(mutableValue, newValue) {
            print("MUTABLE VALUE CHANGE: \(newValue)")
            selfInitiatedChangeCount += 1
            print("SIC COUNT 1: \(selfInitiatedChangeCount)")
            notify.valueWillChange()
            mutableValue = newValue
            notify.valueChanging(change: newValue, metadata: metadata)
            notify.valueDidChange()
            selfInitiatedChangeCount -= 1
            print("SIC COUNT 2: \(selfInitiatedChangeCount)")
        }
    }
    
    internal override func getValue() -> T {
        return mutableValue
    }
    
    /// Note: This is called in the case when the "other" property in a binding has changed its value.
    internal override func setValue(newValue: T, _ metadata: ChangeMetadata) {
        if valueChanging(mutableValue, newValue) {
            print("MUTABLE VALUE SET: \(newValue)")
            selfInitiatedChangeCount += 1
            print("SIC COUNT 1: \(selfInitiatedChangeCount)")
            notify.valueWillChange()
            mutableValue = newValue
            didSet?(newValue, metadata)
            notify.valueChanging(change: newValue, metadata: metadata)
            notify.valueDidChange()
            selfInitiatedChangeCount -= 1
            print("SIC COUNT 2: \(selfInitiatedChangeCount)")
        }
    }
}

public func mutableValueProperty<T>(initialValue: T, valueChanging: (T, T) -> Bool, _ changeHandler: ChangeHandler, _ didSet: BindableProperty<T>.Setter? = nil) -> MutableValueProperty<T> {
    return MutableValueProperty(initialValue, changeHandler: changeHandler, valueChanging: valueChanging, didSet: didSet)
}

// TODO: Drop the variants that don't require changeHandler (to make sure all clients are properly migrated to the new system)
public func mutableValueProperty<T>(initialValue: T, valueChanging: (T, T) -> Bool, _ didSet: BindableProperty<T>.Setter? = nil) -> MutableValueProperty<T> {
    return MutableValueProperty(initialValue, changeHandler: ChangeHandler(), valueChanging: valueChanging, didSet: didSet)
}

public func mutableValueProperty<T: Equatable>(initialValue: T, _ changeHandler: ChangeHandler, _ didSet: BindableProperty<T>.Setter? = nil) -> MutableValueProperty<T> {
    return MutableValueProperty(initialValue, changeHandler: changeHandler, valueChanging: valueChanging, didSet: didSet)
}

public func mutableValueProperty<T: Equatable>(initialValue: T, _ didSet: BindableProperty<T>.Setter? = nil) -> MutableValueProperty<T> {
    return MutableValueProperty(initialValue, changeHandler: ChangeHandler(), valueChanging: valueChanging, didSet: didSet)
}

public func mutableValueProperty<T: Equatable>(initialValue: T?, _ changeHandler: ChangeHandler, _ didSet: BindableProperty<T?>.Setter? = nil) -> MutableValueProperty<T?> {
    return MutableValueProperty(initialValue, changeHandler: changeHandler, valueChanging: valueChanging, didSet: didSet)
}

public func mutableValueProperty<T: Equatable>(initialValue: T?, _ didSet: BindableProperty<T?>.Setter? = nil) -> MutableValueProperty<T?> {
    return MutableValueProperty(initialValue, changeHandler: ChangeHandler(), valueChanging: valueChanging, didSet: didSet)
}

public class ExternalValueProperty<T>: ReadWriteProperty<T> {
    public typealias Getter = () -> T

    private let get: Getter
    private let set: Setter
    
    // TODO: Drop the default changeHandler value (to make sure all clients are properly migrated to the new system)
    public init(get: Getter, set: Setter, changeHandler: ChangeHandler = ChangeHandler()) {
        self.get = get
        self.set = set
        
        let (signal, notify) = Signal<T>.pipe()
        super.init(
            signal: signal,
            notify: notify,
            changeHandler: changeHandler
        )
    }
    
    /// Called to notify observers that the underlying external value has been changed.
    public func changed(transient transient: Bool) {
        selfInitiatedChangeCount += 1
        notify.valueWillChange()
        notify.valueChanging(change: getValue(), metadata: ChangeMetadata(transient: transient))
        notify.valueDidChange()
        selfInitiatedChangeCount -= 1
    }
    
    internal override func getValue() -> T {
        return get()
    }
    
    /// Note: This is called in the case when the "other" property in a binding has changed its value.
    internal override func setValue(newValue: T, _ metadata: ChangeMetadata) {
        notify.valueWillChange()
        set(newValue, metadata)
        notify.valueChanging(change: newValue, metadata: metadata)
        notify.valueDidChange()
    }
}

public class ActionProperty: WriteOnlyProperty<()> {

    public init(_ action: () -> Void) {
        super.init(set: { _ in
            action()
        })
    }
}

// This syntax is borrowed from ReactiveCocoa.
infix operator <~ {
    associativity right
    precedence 93
}

public func <~ <T, RHS: ReadablePropertyType where RHS.Value == T, RHS.SignalChange == T>(lhs: BindableProperty<T>, rhs: RHS) -> Binding {
    return lhs.bind(rhs.signal, initialValue: rhs.value, owner: rhs)
}

public func <~ <T, RHS: AsyncReadablePropertyType where RHS.Value == T, RHS.SignalChange == T>(lhs: BindableProperty<T>, rhs: RHS) -> Binding {
    rhs.start()
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

public func <~> <T>(lhs: ReadWriteProperty<T>, rhs: AsyncReadWriteProperty<T>) -> Binding {
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
