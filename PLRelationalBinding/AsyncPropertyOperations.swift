//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

extension AsyncReadablePropertyType where Self.Value == Self.SignalChange {
    /// Returns an AsyncReadableProperty whose value is derived from this property's `value`.
    /// The given `transform` will be applied whenever this property's value changes.
    public func map<U>(_ transform: @escaping (Self.Value) -> U) -> AsyncReadableProperty<U> {
        let initialValue = self.value.map(transform)
        return AsyncReadableProperty(initialValue: initialValue, signal: self.signal.map(transform))
    }
    
    /// Returns an AsyncReadableProperty whose value is derived from the given property's `value`.
    /// The given `transform` will be applied whenever this property's value changes, and in turn
    /// the property returned by `transform` becomes the new source of values.
    public func flatMap<P: AsyncReadablePropertyType>(_ transform: @escaping (Self.Value) -> P) -> AsyncReadableProperty<P.Value>
        where P.Value == P.SignalChange
    {
        return FlatMappedValueProperty(property: self, transform: transform)
    }
}

/// Returns an AsyncReadableProperty whose value is a tuple (pair) containing the `value` from
/// each of the given properties.  The returned property's `value` will contain a fresh tuple
/// any time the value of either input changes.
public func zip<LHS: AsyncReadablePropertyType, RHS: AsyncReadablePropertyType>(_ lhs: LHS, _ rhs: RHS) -> AsyncReadableProperty<(LHS.Value, RHS.Value)>
    where LHS.Value == LHS.SignalChange, RHS.Value == RHS.SignalChange
{
    // TODO: initialValue?
    return AsyncReadableProperty(initialValue: nil, signal: zip(lhs.signal, rhs.signal))
}

/// Returns an AsyncReadableProperty whose value is the negation of the boolean value of the given property.
public func not<P: AsyncReadablePropertyType>(_ property: P) -> AsyncReadableProperty<Bool>
    where P.Value == Bool, P.SignalChange == Bool
{
    return property.map{ !$0 }
}

prefix operator !

public prefix func !<P: AsyncReadablePropertyType>(property: P) -> AsyncReadableProperty<Bool>
    where P.Value == Bool, P.SignalChange == Bool
{
    return not(property)
}

private class FlatMappedValueProperty<T>: AsyncReadableProperty<T> {
    private let underlying: AsyncPropertyType
    private var startFunc: (() -> Void)?
    private var underlyingRemoval: ObserverRemoval?
    private var mappedProperty: AsyncPropertyType?
    private var mappedRemoval: ObserverRemoval?
    
    init<P: AsyncReadablePropertyType, Q: AsyncReadablePropertyType>(property: P, transform: @escaping (P.Value) -> Q)
        where P.Value == P.SignalChange, Q.Value == Q.SignalChange, T == Q.Value
    {
        self.underlying = property
        
        let initialMappedProperty = property.value.map(transform)
        let initialValue = initialMappedProperty?.value

        let (signal, notify) = Signal<Q.Value>.pipe()
        
        super.init(initialValue: initialValue, signal: signal)

        func observeMappedProperty(_ prop: Q) {
            self.mappedProperty = prop
            self.mappedRemoval = prop.signal.observe(SignalObserver(
                valueWillChange: {
                    notify.valueWillChange()
                },
                valueChanging: { mappedChange, mappedMetadata in
                    notify.valueChanging(mappedChange, mappedMetadata)
                },
                valueDidChange: {
                    notify.valueDidChange()
                }
            ))
        }
        
        self.startFunc = {
            // Observe the underlying property
            self.underlyingRemoval = property.signal.observe(SignalObserver(
                valueWillChange: {
                    notify.valueWillChange()
                },
                valueChanging: { [weak self] change, metadata in
                    // Stop observing the previous mapped property
                    // TODO: Should we stop observing earlier (in valueWillChange)?
                    self?.mappedRemoval?()
                    self?.mappedProperty = nil
                    
                    // Compute the new mapped property
                    let mappedProperty = transform(change)
                    
                    // Observe the new property's signal
                    observeMappedProperty(mappedProperty)
                    
//                    // Deliver the mapped property's initial value, if needed
//                    if let initialValue = mappedProperty.value {
//                        notify.valueWillChange()
//                        notify.valueChanging(initialValue, transient: false)
//                        notify.valueDidChange()
//                    }
                    
//                    // Start the new property
//                    mappedProperty.start()
                },
                valueDidChange: {
                    notify.valueDidChange()
                }
            ))

//            // Start the underlying property
//            property.start()
            
            if let initialProperty = initialMappedProperty {
                // Observe the initial mapped property's signal
                observeMappedProperty(initialProperty)
                
//                // Start the initial mapped property
//                initialProperty.start()
            }
        }
    }

    deinit {
        underlyingRemoval?()
        mappedRemoval?()
    }
    
//    fileprivate override func start() {
//        startFunc?()
//        startFunc = nil
//        super.start()
//    }
}

private class BinaryOpValueProperty<T>: AsyncReadableProperty<T> {
    private let underlying1: AsyncPropertyType
    private let underlying2: AsyncPropertyType
    private var startFunc: (() -> Void)?
    private var removal1: ObserverRemoval?
    private var removal2: ObserverRemoval?

    init<LHS: AsyncReadablePropertyType, RHS: AsyncReadablePropertyType>(_ lhs: LHS, _ rhs: RHS, _ f: @escaping (LHS.Value, RHS.Value) -> T)
        where LHS.Value == LHS.SignalChange, RHS.Value == RHS.SignalChange
    {
        self.underlying1 = lhs
        self.underlying2 = rhs
        
        let (signal, notify) = Signal<T>.pipe()
        
        // Note that we don't deliver a pair until both underlying values are defined
        var lhsValue = lhs.value
        var rhsValue = rhs.value
        func notifyChanging(_ metadata: ChangeMetadata) {
            if let lv = lhsValue, let rv = rhsValue {
                notify.valueChanging(f(lv, rv), metadata)
            }
        }

        let initialValue: T?
        if let lv = lhsValue, let rv = rhsValue {
            initialValue = f(lv, rv)
        } else {
            initialValue = nil
        }
        super.init(initialValue: initialValue, signal: signal)
        
        self.startFunc = {
            // Observe the underlying signals
            self.removal1 = lhs.signal.observe(SignalObserver(
                valueWillChange: {
                    notify.valueWillChange()
                },
                valueChanging: { change, metadata in
                    lhsValue = change
                    notifyChanging(metadata)
                },
                valueDidChange: {
                    notify.valueDidChange()
                }
            ))
            self.removal2 = rhs.signal.observe(SignalObserver(
                valueWillChange: {
                    notify.valueWillChange()
                },
                valueChanging: { change, metadata in
                    rhsValue = change
                    notifyChanging(metadata)
                },
                valueDidChange: {
                    notify.valueDidChange()
                }
            ))
            
//            // Start the underlying properties
//            lhs.start()
//            rhs.start()
            
//            // Take on the combined change count of the underlying signals
//            signal.setChangeCount(lhs.signal.changeCount + rhs.signal.changeCount)
        }
    }

    deinit {
        removal1?()
        removal2?()
    }
//    
//    fileprivate override func start() {
//        startFunc?()
//        startFunc = nil
//        super.start()
//    }
}
