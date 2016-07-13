//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

public protocol AsyncReadablePropertyType: class {
    associatedtype Value
    
    var value: Value? { get }
    var signal: Signal<Value> { get }
    
    func start()
}

/// A concrete readable property whose value is fetched asynchronously.
public class AsyncReadableProperty<T>: AsyncReadablePropertyType {
    public typealias Value = T
    
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

/// A concrete property that can be updated when bound to another property.
public class AsyncBindableProperty<T> {
    
    public typealias Setter = (T, ChangeMetadata) -> Void
    
    // Note: This is exposed as `internal` only for easier access by tests.
    internal let set: Setter
    private let changeHandler: ChangeHandler
    
    private var bindings: [UInt64: Binding] = [:]
    private var nextBindingID: UInt64 = 0
    
    internal init(set: Setter, changeHandler: ChangeHandler) {
        self.set = set
        self.changeHandler = changeHandler
    }
    
    deinit {
        for (_, binding) in bindings {
            binding.unbind()
        }
    }
    
//    /// Establishes a unidirectional binding between this property and the given signal.
//    /// When the other property's value changes, this property's value will be updated.
//    /// Note that calling `bind` will cause this property to take on the given initial
//    /// value immediately.
//    private func bind(signal: Signal<T>, initialValue: T?, owner: AnyObject) -> Binding {
//        
//        if let initialValue = initialValue {
//            // Make this property take on the given initial value
//            // TODO: Maybe only do this if this is the first thing being bound (i.e., when
//            // the set of bindings is empty)
//            // TODO: Does metadata have meaning here?
//            self.set(initialValue, ChangeMetadata(transient: true))
//        }
//        
//        // Observe the given signal for changes
//        let signalObserverRemoval = signal.observe(SignalObserver(
//            // TODO: Is this the right place for the change handler stuff?
//            valueWillChange: { [weak self] in
//                self?.changeHandler.willChange()
//            },
//            valueChanging: { [weak self] value, metadata in
//                guard let weakSelf = self else { return }
//                weakSelf.set(value, metadata)
//            },
//            valueDidChange: { [weak self] in
//                self?.changeHandler.didChange()
//            }
//        ))
//        
//        // Save and return the binding
//        let bindingID = nextBindingID
//        let binding = Binding(signalOwner: owner, removal: { [weak self] in
//            signalObserverRemoval()
//            self?.bindings.removeValueForKey(bindingID)?.unbind()
//        })
//        nextBindingID += 1
//        bindings[bindingID] = binding
//        return binding
//    }
//    
//    /// Unbinds all existing bindings.
//    public func unbindAll() {
//        for (_, binding) in bindings {
//            binding.unbind()
//        }
//        bindings.removeAll()
//    }
}

public class AsyncReadWriteProperty<T>: AsyncBindableProperty<T>, AsyncReadablePropertyType {
    public typealias Value = T
    public typealias Getter = () -> T?
    
    public var value: T? {
        return get()
    }
    public let signal: Signal<T>
    
    private let get: Getter
    
    internal init(get: Getter, set: Setter, signal: Signal<T>, changeHandler: ChangeHandler) {
        self.get = get
        self.signal = signal
        super.init(set: set, changeHandler: changeHandler)
    }
    
    public func start() {
        signal.start()
    }
    
//    /// Establishes a bidirectional binding between this property and the given property.
//    /// When this property's value changes, the other property's value will be updated and
//    /// vice versa.  Note that calling `bindBidi` will cause this property to take on the
//    /// other property's value immedately.
//    public func bindBidi(other: AsyncReadWriteProperty<T>) -> Binding {
//        return connectBidi(
//            other,
//            initial: {
//                if let otherValue = other.get() {
//                    self.set(otherValue, ChangeMetadata(transient: true))
//                }
//            },
//            forward: { .Change($0) },
//            reverse: { .Change($0) }
//        )
//    }
//    
//    private func connectBidi<U>(other: AsyncReadWriteProperty<U>, initial: () -> Void, forward: T -> ChangeResult<U>, reverse: U -> ChangeResult<T>) -> Binding {
//        var selfInitiatedChange = false
//        
//        // Observe the signal of the other property
//        let signalObserverRemoval1 = other.signal.observe(SignalObserver(
//            // TODO: How to deal with ChangeHandler here?
//            valueWillChange: {},
//            valueChanging: { [weak self] value, metadata in
//                if selfInitiatedChange { return }
//                if case .Change(let newValue) = reverse(value) {
//                    selfInitiatedChange = true
//                    self?.set(newValue, metadata)
//                    selfInitiatedChange = false
//                }
//            },
//            // TODO: How to deal with ChangeHandler here?
//            valueDidChange: {}
//        ))
//        
//        // Make the other property observe this property's signal
//        let signalObserverRemoval2 = signal.observe(SignalObserver(
//            // TODO: How to deal with ChangeHandler here?
//            valueWillChange: {},
//            valueChanging: { [weak other] value, metadata in
//                if selfInitiatedChange { return }
//                if case .Change(let newValue) = forward(value) {
//                    selfInitiatedChange = true
//                    other?.set(newValue, metadata)
//                    selfInitiatedChange = false
//                }
//            },
//            // TODO: How to deal with ChangeHandler here?
//            valueDidChange: {}
//        ))
//        
//        // Make this property take on the initial value from the other property (or vice versa)
//        selfInitiatedChange = true
//        initial()
//        selfInitiatedChange = false
//        
//        // Save and return the binding
//        let bindingID = nextBindingID
//        let binding = Binding(signalOwner: other, removal: { [weak self] in
//            signalObserverRemoval1()
//            signalObserverRemoval2()
//            self?.bindings.removeValueForKey(bindingID)?.unbind()
//        })
//        nextBindingID += 1
//        bindings[bindingID] = binding
//        return binding
//    }
}
