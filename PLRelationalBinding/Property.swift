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
    private var signalOwner: AnyObject?

    private var removal: ((Void) -> Void)?
    
    init(signalOwner: AnyObject, removal: @escaping (Void) -> Void) {
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

///// A concrete property that is readable and observable.
open class ReadableProperty<T>: ReadablePropertyType {
    public typealias Value = T
    public typealias Change = T
    
    public private(set) var value: T
    public let signal: Signal<T>
    private let notify: Signal<T>.Notify
    private let changing: (T, T) -> Bool
    
    public init(initialValue: T, changing: @escaping (T, T) -> Bool) {
        self.value = initialValue
        self.changing = changing
        
        let pipeSignal = PipeSignal<T>()
        self.signal = pipeSignal
        self.notify = SignalObserver(
            valueWillChange: pipeSignal.notifyWillChange,
            valueChanging: pipeSignal.notifyChanging,
            valueDidChange: pipeSignal.notifyDidChange
        )
        
        // Deliver the current value when an observer attaches to our signal
        pipeSignal.onObserve = { [weak self] observer in
            guard let strongSelf = self else { return }
            observer.valueWillChange()
            observer.valueChanging(strongSelf.value, transient: false)
            observer.valueDidChange()
        }
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
    /// When the other signal's value changes, this property's value will be updated.
    /// Note that calling `bind` will cause this property to take on the initial value
    /// of the other property if it is available.
    fileprivate func bind(_ signal: Signal<T>, initialValue: T?, owner: AnyObject) -> Binding {
        // TODO: initialValue is unused!!!!!
        
        // Keep track of Will/DidChange events for this binding
        var changeCount = 0
        
        // Observe the given signal for changes
        let signalObserverRemoval = signal.observe(SignalObserver(
            valueWillChange: { [weak self] in
                changeCount += 1
                self?.changeHandler.willChange()
            },
            valueChanging: { [weak self] value, metadata in
                guard let strongSelf = self else { return }
                strongSelf.setValue(value, metadata)
            },
            valueDidChange: { [weak self] in
                changeCount -= 1
                self?.changeHandler.didChange()
            }
        ))

        // Save and return the binding
        let bindingID = nextBindingID
        let binding = Binding(signalOwner: owner, removal: { [weak self] in
            signalObserverRemoval()
            if let strongSelf = self {
                if let binding = strongSelf.bindings.removeValue(forKey: bindingID) {
                    binding.unbind()
                    strongSelf.changeHandler.decrementCount(changeCount)
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
        
        // The change count should have been reset after all the preceding calls to `unbind`, but
        // just in case it wasn't, let's do that here
        changeHandler.resetCount()
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

    public var value: T {
        return getValue()
    }
    public let signal: Signal<T>
    fileprivate let notify: Signal<T>.Notify
    
    internal override init(changeHandler: ChangeHandler) {
        let (pipeSignal, pipeNotify) = Signal<T>.pipe()
        self.signal = pipeSignal
        self.notify = pipeNotify

        super.init(changeHandler: changeHandler)
        
        // Deliver the current value when an observer attaches to our signal
        pipeSignal.onObserve = { [weak self] observer in
            guard let strongSelf = self else { return }
            observer.valueWillChange()
            observer.valueChanging(strongSelf.value, transient: false)
            observer.valueDidChange()
        }
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
    public func bindBidi(_ other: ReadWriteProperty<T>) -> Binding {
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
    public func connectBidi<U>(_ other: ReadWriteProperty<U>, forward: @escaping (T) -> ChangeResult<U>, reverse: @escaping (U) -> ChangeResult<T>) -> Binding {
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

    private func connectBidi<U>(_ other: ReadWriteProperty<U>, initial: () -> Void, forward: @escaping (T) -> ChangeResult<U>, reverse: @escaping (U) -> ChangeResult<T>) -> Binding {
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
            // TODO: Should we be attempting to modify other's ChangeHandler?
            valueWillChange: {},
            valueChanging: { [weak other] value, metadata in
                if selfInitiatedChange { return }
                if case .change(let newValue) = forward(value) {
                    selfInitiatedChange = true
                    other?.setValue(newValue, metadata)
                    selfInitiatedChange = false
                }
            },
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
    public func bindBidi(_ other: AsyncReadWriteProperty<T>) -> Binding {
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
        otherInitiatedChange = true
        initial()
        otherInitiatedChange = false

//        // Start the other property's signal
//        other.start()
        
        // Take on the given signal's change count; note that we only do this in the case where
        // there wasn't an initial value, because otherwise deliverInitial will be true and
        // the observer's valueWillChange will be called and omg this is so complicated
//        if other.value != nil {
//            changeHandler.incrementCount(other.signal.changeCount)
//        }

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

/// Returns a ReadableProperty whose value never changes.
public func constantValueProperty<T>(_ value: T) -> ReadableProperty<T> {
    return ReadableProperty(initialValue: value, changing: { _ in false })
}

public final class MutableValueProperty<T>: ReadWriteProperty<T> {

    private let valueChanging: (T, T) -> Bool
    private let didSet: Setter?
    private var mutableValue: T
    
    fileprivate init(_ initialValue: T, changeHandler: ChangeHandler, valueChanging: @escaping (T, T) -> Bool, didSet: Setter?) {
        self.valueChanging = valueChanging
        self.didSet = didSet
        self.mutableValue = initialValue
        
        super.init(changeHandler: changeHandler)
    }
    
    /// Called to update the underlying value and notify observers that the value has been changed.
    public func change(_ newValue: T, transient: Bool) {
        change(newValue, metadata: ChangeMetadata(transient: transient))
    }
    
    /// Called to update the underlying value and notify observers that the value has been changed.
    public func change(_ newValue: T, metadata: ChangeMetadata) {
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

public func mutableValueProperty<T>(_ initialValue: T?, _ didSet: BindableProperty<T?>.Setter? = nil) -> MutableValueProperty<T?> {
    return MutableValueProperty(initialValue, changeHandler: ChangeHandler(), valueChanging: valueChanging, didSet: didSet)
}

public func mutableValueProperty<T: Equatable>(_ initialValue: T?, _ changeHandler: ChangeHandler, _ didSet: BindableProperty<T?>.Setter? = nil) -> MutableValueProperty<T?> {
    return MutableValueProperty(initialValue, changeHandler: changeHandler, valueChanging: valueChanging, didSet: didSet)
}

public func mutableValueProperty<T: Equatable>(_ initialValue: T?, _ didSet: BindableProperty<T?>.Setter? = nil) -> MutableValueProperty<T?> {
    return MutableValueProperty(initialValue, changeHandler: ChangeHandler(), valueChanging: valueChanging, didSet: didSet)
}

public func mutableValueProperty<T: Equatable>(_ initialValue: [T], _ didSet: BindableProperty<[T]>.Setter? = nil) -> MutableValueProperty<[T]> {
    return MutableValueProperty(initialValue, changeHandler: ChangeHandler(), valueChanging: valueChanging, didSet: didSet)
}

public final class ExternalValueProperty<T>: ReadWriteProperty<T> {
    public typealias Getter = () -> T

    /// When `true`, any changes supplied by a bound property will be ignored.  This is mainly useful
    /// when a UI control has the concept of "edit mode" (e.g. a text field) and is primarily supplying values
    /// *to* a bidirectionally-bound property but is not likely to receive values *from* that property while
    /// in edit mode.
    public var exclusiveMode: Bool = false
    
    private let get: Getter
    private let set: Setter
    
    public init(get: @escaping Getter, set: @escaping Setter, changeHandler: ChangeHandler = ChangeHandler()) {
        self.get = get
        self.set = set
        
        super.init(changeHandler: changeHandler)
    }
    
    /// Called to notify observers that the underlying external value has been changed.
    public func changed(transient: Bool) {
        notify.valueWillChange()
        notify.valueChanging(getValue(), ChangeMetadata(transient: transient))
        notify.valueDidChange()
    }
    
    internal override func getValue() -> T {
        return get()
    }
    
    /// Note: This is called in the case when the "other" property in a binding has changed its value.
    internal override func setValue(_ newValue: T, _ metadata: ChangeMetadata) {
        if exclusiveMode { return }
        
        notify.valueWillChange()
        set(newValue, metadata)
        notify.valueChanging(newValue, metadata)
        notify.valueDidChange()
    }
}

public class ActionProperty<T>: WriteOnlyProperty<T> {

    public init(_ action: @escaping (T) -> Void) {
        super.init(set: { param, _ in
            action(param)
        })
    }
}

precedencegroup PropertyOperatorPrecedence {
    associativity: right
    higherThan: AssignmentPrecedence
}

extension BindableProperty {
    /// Establishes a unidirectional binding between this property and the given property.
    /// When the other property's value changes, this property's value will be updated.
    /// Note that calling `bind` will cause this property to take on the given initial
    /// value immediately if non-nil, otherwise will take on the given property's value.
    @discardableResult public func bind<RHS: ReadablePropertyType>(_ rhs: RHS, initialValue: T? = nil) -> Binding where RHS.Value == T, RHS.SignalChange == T {
        return self.bind(rhs.signal, initialValue: initialValue ?? rhs.value, owner: rhs)
    }

    /// Establishes a unidirectional binding between this property and the given property.
    /// When the other property's value changes, this property's value will be updated.
    /// Note that calling `bind` will `start` the other property and will cause this property
    /// to take on the given initial value if non-nil, otherwise will take on the given
    /// property's value (if defined).
    @discardableResult public func bind<RHS: AsyncReadablePropertyType>(_ rhs: RHS, initialValue: T? = nil) -> Binding where RHS.Value == T, RHS.SignalChange == T {
        return self.bind(rhs.signal, initialValue: initialValue ?? rhs.value, owner: rhs)
    }
}

// This syntax is borrowed from ReactiveCocoa.
infix operator <~ : PropertyOperatorPrecedence

@discardableResult public func <~ <T, RHS: ReadablePropertyType>(lhs: BindableProperty<T>, rhs: RHS) -> Binding where RHS.Value == T, RHS.SignalChange == T {
    return lhs.bind(rhs)
}

@discardableResult public func <~ <T, RHS: AsyncReadablePropertyType>(lhs: BindableProperty<T>, rhs: RHS) -> Binding where RHS.Value == T, RHS.SignalChange == T {
    return lhs.bind(rhs)
}

// TODO: It seems that `~>` is defined somewhere already (not sure where exactly), so to avoid
// conflicts we use `~~>` here instead
infix operator ~~> : PropertyOperatorPrecedence

@discardableResult public func ~~> <T>(lhs: Signal<T>, rhs: ActionProperty<T>) -> Binding {
    // TODO: We invent an owner here; what if no one else owns the signal?
    return rhs.bind(lhs, initialValue: nil, startProp: {}, owner: "" as AnyObject)
}

infix operator <~> : PropertyOperatorPrecedence

@discardableResult public func <~> <T>(lhs: ReadWriteProperty<T>, rhs: ReadWriteProperty<T>) -> Binding {
    return lhs.bindBidi(rhs)
}

@discardableResult public func <~> <T>(lhs: ReadWriteProperty<T>, rhs: AsyncReadWriteProperty<T>) -> Binding {
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
