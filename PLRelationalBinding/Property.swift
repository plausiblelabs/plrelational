//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

/// Describes the result of a `connectBidi` transformation.
public enum ChangeResult<T> {
    /// The given value should be changed.
    case change(T)
    
    /// No change should be applied.
    case noChange
}

/// A handle to a binding that is established by one of the `bind` or `connect` methods.
public class Binding {

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

    /// Forcibly breaks this binding.
    public func unbind() {
        signalOwner = nil
        removal?()
        removal = nil
    }
}

/// Represents a property, which exposes a value and allows observers to see when that value has changed.
public protocol ReadablePropertyType: class {
    /// The property's value type.
    associatedtype Value

    /// The value exposed by this property.
    var value: Value { get }
    
    /// The signal that delivers value change events.
    var signal: Signal<Value> { get }
}

/// A concrete property that is readable and observable.
open class ReadableProperty<T>: ReadablePropertyType {
    public typealias Value = T
    
    private let underlyingSignal: Signal<T>
    private var underlyingRemoval: ObserverRemoval?
    public let signal: Signal<T>
    
    private var mutableValue: T?
    public var value: T {
        if mutableValue == nil {
            // Note that `mutableValue` will be nil until either a) an observer is attached to `signal`
            // or b) someone tries to access `value` (in which case we attach a dummy observer to kick
            // the signal into action)
            let removal = signal.observe{ _ in }
            removal()
        }
        return mutableValue!
    }

    private let changing: (T, T) -> Bool
    
    /// Initializes the property from the given Signal and a function that is used to suppress redundant changes.
    public init(signal: Signal<T>, changing: @escaping (T, T) -> Bool) {
        self.changing = changing

        let pipeSignal = PipeSignal<T>()
        self.signal = pipeSignal
        self.underlyingSignal = signal

        func isChange(_ current: T?, _ new: T) -> Bool {
            if let current = current {
                return changing(current, new)
            } else {
                return true
            }
        }
        
        // Deliver the current value when an observer attaches to our signal
        pipeSignal.onObserve = { [weak self] observer in
            guard let strongSelf = self else { return }
            if strongSelf.underlyingRemoval == nil {
                // Observe the underlying signal the first time someone observes our public signal.
                // Note that since ReadableProperty is expected to be fully synchronous, our observer
                // will error (fatally) upon receiving an asynchronous Begin/EndPossibleAsync event.
                strongSelf.underlyingRemoval = strongSelf.underlyingSignal.observeSynchronousValueChanging{ [weak self] newValue, metadata in
                    guard let strongSelf = self else { return }
                    if strongSelf.underlyingRemoval == nil || isChange(strongSelf.mutableValue, newValue) {
                        strongSelf.mutableValue = newValue
                        pipeSignal.notifyValueChanging(newValue, metadata)
                    }
                }
                if strongSelf.mutableValue == nil {
                    fatalError("Synchronous signals *must* deliver a `valueChanging` event when observer is attached")
                }
            } else {
                // For subsequent observers, deliver our current value to just the observer being attached
                observer.notifyValueChanging(strongSelf.value, transient: false)
            }
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
    /// delivered by the given signal.  If the signal cannot provide an initial value,
    /// this property will take on the given `initialValue` if non-nil.
    fileprivate func bind(_ signal: Signal<T>, owner: AnyObject, initialValue: T? = nil) -> Binding {
        // Keep track of Begin/EndPossibleAsync events for this binding
        var changeCount = 0
        
        // Observe the given signal for changes
        var setInitial = false
        let signalObserverRemoval = signal.observe{ [weak self] event in
            switch event {
            case .beginPossibleAsyncChange:
                changeCount += 1
                self?.changeHandler.willChange()
            
            case let .valueChanging(newValue, metadata):
                self?.setValue(newValue, metadata)
                setInitial = true
            
            case .endPossibleAsyncChange:
                changeCount -= 1
                self?.changeHandler.didChange()
            }
        }

        if !setInitial {
            if let initialValue = initialValue {
                self.setValue(initialValue, ChangeMetadata(transient: false))
            }
        }
        
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

/// A concrete property that can be updated, but not read from.
open class WriteOnlyProperty<T>: BindableProperty<T> {

    fileprivate let set: Setter
    
    public init(set: @escaping Setter, changeHandler: ChangeHandler = ChangeHandler()) {
        self.set = set
        super.init(changeHandler: changeHandler)
    }
    
    override internal func setValue(_ newValue: T, _ metadata: ChangeMetadata) {
        set(newValue, metadata)
    }
}

/// Base class for properties that can be both read from and written to, i.e. is capable of bidirectional binding.
open class ReadWriteProperty<T>: BindableProperty<T>, ReadablePropertyType {
    public typealias Value = T

    public var value: T {
        return getValue()
    }
    fileprivate let sourceSignal: PipeSignal<T>
    public var signal: Signal<T> { return sourceSignal }
    
    internal override init(changeHandler: ChangeHandler) {
        self.sourceSignal = PipeSignal()

        super.init(changeHandler: changeHandler)
        
        // Deliver the current value when an observer attaches to our signal
        sourceSignal.onObserve = { [weak self] observer in
            guard let strongSelf = self else { return }
            observer.notifyValueChanging(strongSelf.value, transient: false)
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
            leftToRight: { value, isInitial in
                // We don't want `other` to take on `self`'s value initially, but we do want
                // it when `self` changes subsequently
                if isInitial {
                    return .noChange
                } else {
                    return .change(value)
                }
            },
            rightToLeft: { value, isInitial in
                // We do want `self` to take on `other` value initially, and whenever `other`
                // changes subsequently
                return .change(value)
            }
        )
    }

    /// Establishes a bidirectional connection between this property and the given property,
    /// using `leftToRight` and `rightToLeft` to conditionally apply changes in each direction.
    public func connectBidi<U>(_ rhs: ReadWriteProperty<U>,
                               leftToRight: @escaping (_ value: T, _ isInitial: Bool) -> ChangeResult<U>,
                               rightToLeft: @escaping (_ value: U, _ isInitial: Bool) -> ChangeResult<T>) -> Binding
    {
        var selfInitiatedChange = false
        
        // Make self (the LHS) observe the signal of the RHS property
        var initialRight = true
        let leftObservingRightRemoval = rhs.signal.observeSynchronousValueChanging{ [weak self] value, metadata in
            if selfInitiatedChange { return }
            if case .change(let newValue) = rightToLeft(value, initialRight) {
                selfInitiatedChange = true
                self?.setValue(newValue, metadata)
                selfInitiatedChange = false
            }
            initialRight = false
        }
        
        // Make the RHS property observe the signal of self (the LHS)
        var initialLeft = true
        let rightObservingLeftRemoval = self.signal.observeSynchronousValueChanging{ [weak rhs] value, metadata in
            if selfInitiatedChange { return }
            if case .change(let newValue) = leftToRight(value, initialLeft) {
                selfInitiatedChange = true
                rhs?.setValue(newValue, metadata)
                selfInitiatedChange = false
            }
            initialLeft = false
        }
        
        // Save and return the binding
        let bindingID = nextBindingID
        let binding = Binding(signalOwner: rhs, removal: { [weak self] in
            leftObservingRightRemoval()
            rightObservingLeftRemoval()
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

        // Make the `other` property observe `self`
        var ignoreInitial = true
        let otherObservingSelfRemoval = self.signal.observeSynchronousValueChanging{ [weak other] value, metadata in
            if ignoreInitial {
                // Ignore the initial value that is delivered by `self` when we attach `other` as an observer;
                // we don't want `other` to take on `self`'s value until self actually initiates a change
                ignoreInitial = false
                return
            }
            if !otherInitiatedChange {
                selfInitiatedChange = true
                other?.setValue(value, metadata)
                selfInitiatedChange = false
            }
        }
        
        // Make `self` observe the signal of the `other` property
        let selfObservingOtherRemoval = other.signal.observe{ [weak self] event in
            guard let strongSelf = self else { return }

            switch event {
            case .beginPossibleAsyncChange:
                if selfInitiatedChange {
                    otherChangeCount += 1
                }
                if otherChangeCount == 0 {
                    strongSelf.changeHandler.willChange()
                }
                
            case let .valueChanging(newValue, metadata):
                if otherChangeCount == 0 {
                    otherInitiatedChange = true
                    strongSelf.setValue(newValue, metadata)
                    otherInitiatedChange = false
                }

            case .endPossibleAsyncChange:
                if otherChangeCount > 0 {
                    otherChangeCount -= 1
                } else if otherChangeCount == 0 {
                    strongSelf.changeHandler.didChange()
                }
            }
        }
        
        // Save and return the binding
        let bindingID = nextBindingID
        let binding = Binding(signalOwner: other, removal: { [weak self] in
            otherObservingSelfRemoval()
            selfObservingOtherRemoval()
            self?.bindings.removeValue(forKey: bindingID)?.unbind()
        })
        nextBindingID += 1
        bindings[bindingID] = binding
        return binding
    }
}

/// :nodoc:
/// Returns a ReadableProperty whose value never changes.
public func constantValueProperty<T>(_ value: T) -> ReadableProperty<T> {
    return ReadableProperty(signal: ConstantSignal<T>(value), changing: { _ in false })
}

/// A concrete read/write property whose value can be mutated directly.
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
    public func change(_ newValue: T, transient: Bool = false) {
        change(newValue, metadata: ChangeMetadata(transient: transient))
    }
    
    /// Called to update the underlying value and notify observers that the value has been changed.
    public func change(_ newValue: T, metadata: ChangeMetadata) {
        if valueChanging(mutableValue, newValue) {
            mutableValue = newValue
            sourceSignal.notifyValueChanging(newValue, metadata)
        }
    }
    
    internal override func getValue() -> T {
        return mutableValue
    }
    
    /// Note: This is called in the case when the "other" property in a binding has changed its value.
    internal override func setValue(_ newValue: T, _ metadata: ChangeMetadata) {
        if valueChanging(mutableValue, newValue) {
            mutableValue = newValue
            didSet?(newValue, metadata)
            sourceSignal.notifyValueChanging(newValue, metadata)
        }
    }
}

// TODO: These are all `nodoc` for now to avoid cluttering up the docs.  We should prune them and/or convert them to convenience initializers.

/// :nodoc:
public func mutableValueProperty<T>(_ initialValue: T, valueChanging: @escaping (T, T) -> Bool, _ changeHandler: ChangeHandler, _ didSet: BindableProperty<T>.Setter? = nil) -> MutableValueProperty<T> {
    return MutableValueProperty(initialValue, changeHandler: changeHandler, valueChanging: valueChanging, didSet: didSet)
}

/// :nodoc:
public func mutableValueProperty<T>(_ initialValue: T, valueChanging: @escaping (T, T) -> Bool, _ didSet: BindableProperty<T>.Setter? = nil) -> MutableValueProperty<T> {
    return MutableValueProperty(initialValue, changeHandler: ChangeHandler(), valueChanging: valueChanging, didSet: didSet)
}

/// :nodoc:
public func mutableValueProperty<T: Equatable>(_ initialValue: T, _ changeHandler: ChangeHandler, _ didSet: BindableProperty<T>.Setter? = nil) -> MutableValueProperty<T> {
    return MutableValueProperty(initialValue, changeHandler: changeHandler, valueChanging: valueChanging, didSet: didSet)
}

/// :nodoc:
public func mutableValueProperty<T: Equatable>(_ initialValue: T, _ didSet: BindableProperty<T>.Setter? = nil) -> MutableValueProperty<T> {
    return MutableValueProperty(initialValue, changeHandler: ChangeHandler(), valueChanging: valueChanging, didSet: didSet)
}

/// :nodoc:
public func mutableValueProperty<T>(_ initialValue: T?, _ didSet: BindableProperty<T?>.Setter? = nil) -> MutableValueProperty<T?> {
    return MutableValueProperty(initialValue, changeHandler: ChangeHandler(), valueChanging: valueChanging, didSet: didSet)
}

/// :nodoc:
public func mutableValueProperty<T: Equatable>(_ initialValue: T?, _ changeHandler: ChangeHandler, _ didSet: BindableProperty<T?>.Setter? = nil) -> MutableValueProperty<T?> {
    return MutableValueProperty(initialValue, changeHandler: changeHandler, valueChanging: valueChanging, didSet: didSet)
}

/// :nodoc:
public func mutableValueProperty<T: Equatable>(_ initialValue: T?, _ didSet: BindableProperty<T?>.Setter? = nil) -> MutableValueProperty<T?> {
    return MutableValueProperty(initialValue, changeHandler: ChangeHandler(), valueChanging: valueChanging, didSet: didSet)
}

/// :nodoc:
public func mutableValueProperty<T: Equatable>(_ initialValue: [T], _ didSet: BindableProperty<[T]>.Setter? = nil) -> MutableValueProperty<[T]> {
    return MutableValueProperty(initialValue, changeHandler: ChangeHandler(), valueChanging: valueChanging, didSet: didSet)
}

/// A read/write property whose storage is maintained external to the property.  This is mainly useful for compatibility
/// with existing UI frameworks.  For example, an ExternalValueProperty may be used to add binding support to an existing
/// AppKit control, such as the `stringValue` property of NSTextField.
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
        sourceSignal.notifyValueChanging(getValue(), transient: transient)
    }
    
    internal override func getValue() -> T {
        return get()
    }
    
    /// Note: This is called in the case when the "other" property in a binding has changed its value.
    internal override func setValue(_ newValue: T, _ metadata: ChangeMetadata) {
        if exclusiveMode { return }
        
        set(newValue, metadata)
        sourceSignal.notifyValueChanging(newValue, metadata)
    }
}

/// A convenience form of WriteOnlyProperty that allows a given function to be called whenever a new value is
/// delivered through a binding.  This allows for use of the `~~>` operator that allows for setting up a
/// binding between a UI control that produces "momentary" events (e.g. UIButton clicks) and an ActionProperty
/// that wraps an event handler.
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
    /// Note that calling `bind` will cause this property to take on the `rhs` property's
    /// value immediately, if known, otherwise it will take on `initialValue` if non-nil.
    @discardableResult public func bind<RHS: ReadablePropertyType>(_ rhs: RHS, initialValue: T? = nil) -> Binding where RHS.Value == T {
        return self.bind(rhs.signal, owner: rhs, initialValue: initialValue)
    }

    /// Establishes a unidirectional binding between this property and the given property.
    /// When the other property's value changes, this property's value will be updated.
    /// Note that calling `bind` will `start` the `rhs` property and will cause this property
    /// to take on the `rhs` property's value immediately, if known, otherwise it will take
    /// on `initialValue` if non-nil.
    @discardableResult public func bind<RHS: AsyncReadablePropertyType>(_ rhs: RHS, initialValue: T? = nil) -> Binding where RHS.Value == T, RHS.SignalChange == T {
        return self.bind(rhs.signal, owner: rhs, initialValue: initialValue)
    }
}

// This syntax is borrowed from ReactiveCocoa.
infix operator <~ : PropertyOperatorPrecedence

/// Establishes a unidirectional binding between `lhs` and `rhs`.
/// When the value of the synchronous `rhs` property changes, the value of `lhs` will be updated.
@discardableResult public func <~ <T, RHS: ReadablePropertyType>(lhs: BindableProperty<T>, rhs: RHS) -> Binding where RHS.Value == T {
    return lhs.bind(rhs)
}

/// Establishes a unidirectional binding between `lhs` and `rhs`.
/// When the value of the asynchronous `rhs` property changes, the value of `lhs` will be updated.
@discardableResult public func <~ <T, RHS: AsyncReadablePropertyType>(lhs: BindableProperty<T>, rhs: RHS) -> Binding where RHS.Value == T, RHS.SignalChange == T {
    return lhs.bind(rhs)
}

infix operator ~~> : PropertyOperatorPrecedence

/// Establishes a unidirectional binding such that `rhs` is poked whenever `lhs` delivers a new value.
@discardableResult public func ~~> <T>(lhs: Signal<T>, rhs: ActionProperty<T>) -> Binding {
    // TODO: We invent an owner here; what if no one else owns the signal?
    return rhs.bind(lhs, owner: "" as AnyObject)
}

infix operator <~> : PropertyOperatorPrecedence

/// Establishes a bidirectional binding between the two properties.
/// When one property's value changes, the other property's value will be updated and
/// vice versa.
/// Note that using this operator will cause the `lhs` property to take on the
/// the `rhs` property's value immedately.
@discardableResult public func <~> <T>(lhs: ReadWriteProperty<T>, rhs: ReadWriteProperty<T>) -> Binding {
    return lhs.bindBidi(rhs)
}

/// Establishes a bidirectional binding between the two properties.
/// When one property's value changes, the other property's value will be updated and
/// vice versa.
/// Note that using this operator will cause the `lhs` property to take on the
/// the `rhs` property's value immedately (if the value is defined).
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
