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

public class Property<T> {

    public typealias Setter = (T, ChangeMetadata) -> Void
    
    private let set: Setter
    
    private var bindings: [UInt64: Binding] = [:]
    private var nextBindingID: UInt64 = 0

    public init(_ set: Setter) {
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
    private func bind(signal: Signal<T>, initialValue: T, owner: AnyObject) -> Binding {
        // Make this property take on the given initial value
        // TODO: Maybe only do this if this is the first thing being bound (i.e., when
        // the set of bindings is empty)
        // TODO: Does metadata have meaning here?
        self.set(initialValue, ChangeMetadata(transient: true))
        
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

    public override init(get: Getter, set: Setter, signal: Signal<T>) {
        super.init(get: get, set: set, signal: signal)
    }

    /// Establishes a bidirectional binding between this property and the given property.
    /// When this property's value changes, the other property's value will be updated and
    /// vice versa.  Note that calling `bindBidi` will cause this property to take on the
    /// other property's value immedately.
    public func bindBidi(other: BidiProperty<T>) -> Binding {
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
    public func connectBidi<U>(other: BidiProperty<U>, forward: T -> ChangeResult<U>, reverse: U -> ChangeResult<T>) -> Binding {
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

    private func connectBidi<U>(other: BidiProperty<U>, initial: () -> Void, forward: T -> ChangeResult<U>, reverse: U -> ChangeResult<T>) -> Binding {
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

public class MutableBidiProperty<T>: BidiProperty<T> {

    public let changed: (transient: Bool) -> Void
    
    public init(get: Getter, set: Setter) {
        let signal: Signal<T>
        let notify: Signal<T>.Notify
        (signal, notify) = Signal.pipe()
        
        changed = { (transient: Bool) in
            notify(newValue: get(), metadata: ChangeMetadata(transient: transient))
        }
        
        super.init(
            get: get,
            set: { newValue, metadata in
                set(newValue, metadata)
                notify(newValue: newValue, metadata: metadata)
            },
            signal: signal
        )
    }
}

public class ValueBidiProperty<T>: BidiProperty<T> {

    public let change: (newValue: T, transient: Bool) -> Void
    
    public init(_ initialValue: T, _ didSet: Setter? = nil) {
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
                notify(newValue: newValue, metadata: metadata)
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

public func <~ <T>(lhs: Property<T>, rhs: ObservableValue<T>) -> Binding {
    return lhs.bind(rhs.signal, initialValue: rhs.value, owner: rhs)
}

public func <~ <T>(lhs: Property<T>, rhs: ObservableProperty<T>) -> Binding {
    return lhs.bind(rhs.signal, initialValue: rhs.get(), owner: rhs)
}

infix operator <~> {
    associativity right
    precedence 93
}

public func <~> <T>(lhs: BidiProperty<T>, rhs: BidiProperty<T>) -> Binding {
    return lhs.bindBidi(rhs)
}
