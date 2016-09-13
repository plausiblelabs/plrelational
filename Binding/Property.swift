//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

public enum ChangeResult<T> { case
    change(T),
    noChange
}

open class Binding {

    // XXX: Hang on to the owner of the signal, otherwise if no one else is
    // holding a strong reference to it, it may go away and the signal won't
    // deliver any changes
    // TODO: Find a better solution
    fileprivate var signalOwner: AnyObject?

    fileprivate var removal: ((Void) -> Void)?
    
    init(signalOwner: AnyObject, removal: @escaping (Void) -> Void) {
        self.signalOwner = signalOwner
        self.removal = removal
    }
    
    open func unbind() {
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
open class ReadableProperty<T>: ReadablePropertyType {
    public typealias Value = T
    public typealias Change = T
    
    open fileprivate(set) var value: T
    open let signal: Signal<T>
    fileprivate let notify: Signal<T>.Notify
    fileprivate let changing: (T, T) -> Bool
    
    public init(initialValue: T, signal: Signal<T>, notify: Signal<T>.Notify, changing: @escaping (T, T) -> Bool) {
        self.value = initialValue
        self.signal = signal
        self.notify = notify
        self.changing = changing
    }
    
    internal func setValue(_ newValue: T, _ metadata: ChangeMetadata) {
        if changing(value, newValue) {
            value = newValue
            notify.valueChanging(newValue, metadata)
        }
    }
}

/// A concrete property that can be updated when bound to another property.
open class BindableProperty<T> {
    public typealias Setter = (T, ChangeMetadata) -> Void

    fileprivate let changeHandler: ChangeHandler
    
    fileprivate var bindings: [UInt64: Binding] = [:]
    fileprivate var nextBindingID: UInt64 = 0

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
    internal func setValue(_ newValue: T, _ metadata: ChangeMetadata) {
        fatalError("Must be implemented by subclasses")
    }
    
    /// Establishes a unidirectional binding between this property and the given signal.
    /// When the other property's value changes, this property's value will be updated.
    /// Note that calling `bind` will cause this property to take on the given initial
    /// value immediately.
    fileprivate func bind(_ signal: Signal<T>, initialValue: T?, owner: AnyObject) -> Binding {
        
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
                if let binding = strongSelf.bindings.removeValue(forKey: bindingID) {
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
    open func unbindAll() {
        for (_, binding) in bindings {
            binding.unbind()
        }
        bindings.removeAll()
    }
}

open class WriteOnlyProperty<T>: BindableProperty<T> {

    fileprivate let set: Setter
    
    // TODO: Drop the default value (to make sure all clients are properly migrated to the new system)
    public init(set: @escaping Setter, changeHandler: ChangeHandler = ChangeHandler()) {
        self.set = set
        super.init(changeHandler: changeHandler)
    }
    
    override internal func setValue(_ newValue: T, _ metadata: ChangeMetadata) {
        set(newValue, metadata)
    }
}

open class ReadWriteProperty<T>: BindableProperty<T>, ReadablePropertyType {
    public typealias Value = T

    open var value: T {
        return getValue()
    }
    open let signal: Signal<T>
    fileprivate let notify: Signal<T>.Notify
    
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
    open func bindBidi(_ other: ReadWriteProperty<T>) -> Binding {
        return connectBidi(
            other,
            initial: {
                self.setValue(other.value, ChangeMetadata(transient: true))
            },
            forward: { .change($0) },
            reverse: { .change($0) }
        )
    }

    /// Establishes a bidirectional connection between this property and the given property,
    /// using `forward` and `reverse` to conditionally apply changes in each direction.
    /// Note that calling `connectBidi` will cause the other property to take on this
    /// property's value immediately (this is the opposite behavior from `bindBidi`).
    open func connectBidi<U>(_ other: ReadWriteProperty<U>, forward: @escaping (T) -> ChangeResult<U>, reverse: @escaping (U) -> ChangeResult<T>) -> Binding {
        return connectBidi(
            other,
            initial: {
                if case .change(let initialValue) = forward(self.value) {
                    other.setValue(initialValue, ChangeMetadata(transient: true))
                }
            },
            forward: forward,
            reverse: reverse
        )
    }

    fileprivate func connectBidi<U>(_ other: ReadWriteProperty<U>, initial: () -> Void, forward: @escaping (T) -> ChangeResult<U>, reverse: @escaping (U) -> ChangeResult<T>) -> Binding {
        var selfInitiatedChange = false
        
        // Observe the signal of the other property
        let signalObserverRemoval1 = other.signal.observe(SignalObserver(
            // TODO: How to deal with ChangeHandler here?
            valueWillChange: {},
            valueChanging: { [weak self] value, metadata in
                if selfInitiatedChange { return }
                if case .change(let newValue) = reverse(value) {
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
                if case .change(let newValue) = forward(value) {
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
            self?.bindings.removeValue(forKey: bindingID)?.unbind()
        })
        nextBindingID += 1
        bindings[bindingID] = binding
        return binding
    }
    
    /// Establishes a bidirectional binding between this property and the given property.
    /// When this property's value changes, the other property's value will be updated and
    /// vice versa.  Note that calling `bindBidi` will cause this property to take on the
    /// other property's value immedately (if the value is defined).
    open func bindBidi(_ other: AsyncReadWriteProperty<T>) -> Binding {
        return connectBidi(
            other,
            initial: {
                if let otherValue = other.value {
                    self.setValue(otherValue, ChangeMetadata(transient: true))
                }
            },
            forward: { .change($0) },
            reverse: { .change($0) }
        )
    }
    
    fileprivate func connectBidi<U>(_ other: AsyncReadWriteProperty<U>, initial: () -> Void, forward: @escaping (T) -> ChangeResult<U>, reverse: @escaping (U) -> ChangeResult<T>) -> Binding {
        // This flag is set while `self` is triggering a change to `other`
        var selfInitiatedChange = false
        
        // This flag is set while `other` is triggering a change to `self`
        var otherInitiatedChange = false
        
        // This is the number of async changes pending by the `other` property in response to a change
        // by the `self` property
        // TODO: This system isn't quite sufficient, as it's possible for the `self` property to
        // initiate a number of changes, and while it is in "exclusive" mode (otherChangeCount > 0),
        // the `other` signal's value could have been changed externally (like the underlying relation
        // could have been updated), in which case `self` will end up ignoring those changes.  A more
        // robust system would probably involve giving an identifier to each change as it winds its
        // way through the signal/relation, and providing options to allow the developer to control
        // how conflicts are handled should they arise.
        var otherChangeCount = 0
        
        // Observe the signal of the other property
        let signalObserverRemoval1 = other.signal.observe(SignalObserver(
            valueWillChange: { [weak self] in
                guard let strongSelf = self else { return }
                if selfInitiatedChange {
                    otherChangeCount += 1
                }
                if otherChangeCount == 0 {
                    strongSelf.changeHandler.willChange()
                }
            },
            valueChanging: { [weak self] value, metadata in
                guard let strongSelf = self else { return }
                if otherChangeCount == 0 {
                    if case .change(let newValue) = reverse(value) {
                        otherInitiatedChange = true
                        strongSelf.setValue(newValue, metadata)
                        otherInitiatedChange = false
                    }
                }
            },
            valueDidChange: { [weak self] in
                guard let strongSelf = self else { return }
                if otherChangeCount > 0 {
                    otherChangeCount -= 1
                } else if otherChangeCount == 0 {
                    strongSelf.changeHandler.didChange()
                }
            }
        ))
        
        // Make the other property observe this property's signal
        let signalObserverRemoval2 = signal.observe(SignalObserver(
            valueWillChange: {
                if !otherInitiatedChange {
                    selfInitiatedChange = true
                }
            },
            valueChanging: { [weak other] value, metadata in
                if !otherInitiatedChange {
                    if case .change(let newValue) = forward(value) {
                        other?.setValue(newValue, metadata)
                    }
                }
            },
            valueDidChange: {
                if !otherInitiatedChange {
                    selfInitiatedChange = false
                }
            }
        ))
        
        // Make this property take on the initial value from the other property (or vice versa)
        initial()
        
        // Take on the given signal's change count
        changeHandler.incrementCount(other.signal.changeCount)

        // Start the other property's signal
        other.start()
        
        // Save and return the binding
        let bindingID = nextBindingID
        let binding = Binding(signalOwner: other, removal: { [weak self] in
            signalObserverRemoval1()
            signalObserverRemoval2()
            self?.bindings.removeValue(forKey: bindingID)?.unbind()
        })
        nextBindingID += 1
        bindings[bindingID] = binding
        return binding
    }
}

private class ConstantValueProperty<T>: ReadableProperty<T> {
    fileprivate init(_ value: T) {
        // TODO: Use a no-op signal here
        let (signal, notify) = Signal<T>.pipe()
        super.init(initialValue: value, signal: signal, notify: notify, changing: { _ in false })
    }
}

/// Returns a ValueProperty whose value never changes.  Note that since the value cannot change,
/// observers will never be notified of changes.
public func constantValueProperty<T>(_ value: T) -> ReadableProperty<T> {
    return ConstantValueProperty(value)
}

open class MutableValueProperty<T>: ReadWriteProperty<T> {

    fileprivate let valueChanging: (T, T) -> Bool
    fileprivate let didSet: Setter?
    fileprivate var mutableValue: T
    
    fileprivate init(_ initialValue: T, changeHandler: ChangeHandler, valueChanging: @escaping (T, T) -> Bool, didSet: Setter?) {
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
    open func change(_ newValue: T, transient: Bool) {
        change(newValue, metadata: ChangeMetadata(transient: transient))
    }
    
    /// Called to update the underlying value and notify observers that the value has been changed.
    open func change(_ newValue: T, metadata: ChangeMetadata) {
        if valueChanging(mutableValue, newValue) {
            notify.valueWillChange()
            mutableValue = newValue
            notify.valueChanging(newValue, metadata)
            notify.valueDidChange()
        }
    }
    
    internal override func getValue() -> T {
        return mutableValue
    }
    
    /// Note: This is called in the case when the "other" property in a binding has changed its value.
    internal override func setValue(_ newValue: T, _ metadata: ChangeMetadata) {
        if valueChanging(mutableValue, newValue) {
            notify.valueWillChange()
            mutableValue = newValue
            didSet?(newValue, metadata)
            notify.valueChanging(newValue, metadata)
            notify.valueDidChange()
        }
    }
}

public func mutableValueProperty<T>(_ initialValue: T, valueChanging: @escaping (T, T) -> Bool, _ changeHandler: ChangeHandler, _ didSet: BindableProperty<T>.Setter? = nil) -> MutableValueProperty<T> {
    return MutableValueProperty(initialValue, changeHandler: changeHandler, valueChanging: valueChanging, didSet: didSet)
}

// TODO: Drop the variants that don't require changeHandler (to make sure all clients are properly migrated to the new system)
public func mutableValueProperty<T>(_ initialValue: T, valueChanging: @escaping (T, T) -> Bool, _ didSet: BindableProperty<T>.Setter? = nil) -> MutableValueProperty<T> {
    return MutableValueProperty(initialValue, changeHandler: ChangeHandler(), valueChanging: valueChanging, didSet: didSet)
}

public func mutableValueProperty<T: Equatable>(_ initialValue: T, _ changeHandler: ChangeHandler, _ didSet: BindableProperty<T>.Setter? = nil) -> MutableValueProperty<T> {
    return MutableValueProperty(initialValue, changeHandler: changeHandler, valueChanging: valueChanging, didSet: didSet)
}

public func mutableValueProperty<T: Equatable>(_ initialValue: T, _ didSet: BindableProperty<T>.Setter? = nil) -> MutableValueProperty<T> {
    return MutableValueProperty(initialValue, changeHandler: ChangeHandler(), valueChanging: valueChanging, didSet: didSet)
}

public func mutableValueProperty<T: Equatable>(_ initialValue: T?, _ changeHandler: ChangeHandler, _ didSet: BindableProperty<T?>.Setter? = nil) -> MutableValueProperty<T?> {
    return MutableValueProperty(initialValue, changeHandler: changeHandler, valueChanging: valueChanging, didSet: didSet)
}

public func mutableValueProperty<T: Equatable>(_ initialValue: T?, _ didSet: BindableProperty<T?>.Setter? = nil) -> MutableValueProperty<T?> {
    return MutableValueProperty(initialValue, changeHandler: ChangeHandler(), valueChanging: valueChanging, didSet: didSet)
}

open class ExternalValueProperty<T>: ReadWriteProperty<T> {
    public typealias Getter = () -> T

    fileprivate let get: Getter
    fileprivate let set: Setter
    
    // TODO: Drop the default changeHandler value (to make sure all clients are properly migrated to the new system)
    public init(get: @escaping Getter, set: @escaping Setter, changeHandler: ChangeHandler = ChangeHandler()) {
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
    open func changed(transient: Bool) {
        notify.valueWillChange()
        notify.valueChanging(getValue(), ChangeMetadata(transient: transient))
        notify.valueDidChange()
    }
    
    internal override func getValue() -> T {
        return get()
    }
    
    /// Note: This is called in the case when the "other" property in a binding has changed its value.
    internal override func setValue(_ newValue: T, _ metadata: ChangeMetadata) {
        notify.valueWillChange()
        set(newValue, metadata)
        notify.valueChanging(newValue, metadata)
        notify.valueDidChange()
    }
}

open class ActionProperty: WriteOnlyProperty<()> {

    public init(_ action: @escaping () -> Void) {
        super.init(set: { _ in
            action()
        })
    }
}

precedencegroup PropertyOperatorPrecedence {
    associativity: right
    higherThan: AssignmentPrecedence
}

// This syntax is borrowed from ReactiveCocoa.
infix operator <~ : PropertyOperatorPrecedence

public func <~ <T, RHS: ReadablePropertyType>(lhs: BindableProperty<T>, rhs: RHS) -> Binding where RHS.Value == T, RHS.SignalChange == T {
    return lhs.bind(rhs.signal, initialValue: rhs.value, owner: rhs)
}

public func <~ <T, RHS: AsyncReadablePropertyType>(lhs: BindableProperty<T>, rhs: RHS) -> Binding where RHS.Value == T, RHS.SignalChange == T {
    rhs.start()
    return lhs.bind(rhs.signal, initialValue: rhs.value, owner: rhs)
}

// TODO: It seems that `~>` is defined somewhere already (not sure where exactly), so to avoid
// conflicts we use `~~>` here instead
infix operator ~~> : PropertyOperatorPrecedence

public func ~~> (lhs: Signal<()>, rhs: ActionProperty) -> Binding {
    // TODO: We invent an owner here; what if no one else owns the signal?
    return rhs.bind(lhs, initialValue: nil, owner: "" as AnyObject)
}

infix operator <~> : PropertyOperatorPrecedence

public func <~> <T>(lhs: ReadWriteProperty<T>, rhs: ReadWriteProperty<T>) -> Binding {
    return lhs.bindBidi(rhs)
}

public func <~> <T>(lhs: ReadWriteProperty<T>, rhs: AsyncReadWriteProperty<T>) -> Binding {
    return lhs.bindBidi(rhs)
}

internal func valueChanging<T>(_ v0: T, v1: T) -> Bool {
    return true
}

internal func valueChanging<T: Equatable>(_ v0: T, v1: T) -> Bool {
    return v0 != v1
}

internal func valueChanging<T>(_ v0: T?, v1: T?) -> Bool {
    return true
}

internal func valueChanging<T: Equatable>(_ v0: T?, v1: T?) -> Bool {
    return v0 != v1
}
