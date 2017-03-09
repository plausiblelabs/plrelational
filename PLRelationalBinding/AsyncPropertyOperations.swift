//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

extension AsyncReadablePropertyType where Self.Value == Self.SignalChange {
    /// Returns an AsyncReadableProperty whose value is derived from this property's `value`.
    /// The given `transform` will be applied whenever this property's value changes.
    public func map<U>(_ transform: @escaping (Self.Value) -> U) -> AsyncReadableProperty<U> {
        return MappedValueProperty(property: self, transform: transform)
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
    return BinaryOpValueProperty(lhs, rhs, { ($0, $1) })
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

private class MappedValueProperty<T>: AsyncReadableProperty<T> {
    private let underlying: AsyncPropertyType
    
    init<P: AsyncReadablePropertyType>(property: P, transform: @escaping (P.Value) -> T)
        where P.Value == P.SignalChange
    {
        self.underlying = property

        let initialValue = property.value.map(transform)
        super.init(initialValue: initialValue, signal: property.signal.map(transform))
    }
    
    fileprivate override func start() {
        underlying.start()
        super.start()
    }
}

private class FlatMappedValueProperty<T>: AsyncReadableProperty<T> {
    private let underlying: AsyncPropertyType
    private var startInitial: (() -> Void)?
    private var underlyingRemoval: ObserverRemoval!
    private var mappedRemoval: ObserverRemoval?
    
    init<P: AsyncReadablePropertyType, Q: AsyncReadablePropertyType>(property: P, transform: @escaping (P.Value) -> Q)
        where P.Value == P.SignalChange, Q.Value == Q.SignalChange, T == Q.Value
    {
        self.underlying = property
        
        let initialMappedProperty = property.value.map(transform)
        let initialValue = initialMappedProperty?.value

        self.startInitial = {
            initialMappedProperty?.start()
        }
        
        // TODO: Do we need to take initialMappedProperty.signal's changeCount into account?
        let (signal, notify) = Signal<Q.Value>.pipe(initialChangeCount: property.signal.changeCount)
        
        super.init(initialValue: initialValue, signal: signal)
        
        self.underlyingRemoval = property.signal.observe(SignalObserver(
            valueWillChange: {
                notify.valueWillChange()
            },
            valueChanging: { [weak self] change, metadata in
                // Stop observing the previous mapped property
                // TODO: Should we stop observing earlier (in valueWillChange)?
                self?.mappedRemoval?()
                
                // Compute the new mapped property
                let mappedProperty = transform(change)

                // Observe the new property's signal
                self?.mappedRemoval = mappedProperty.signal.observe(SignalObserver(
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
                
                // Deliver the mapped property's initial value, if needed
                if let initialValue = mappedProperty.value {
                    notify.valueWillChange()
                    notify.valueChanging(initialValue, transient: false)
                    notify.valueDidChange()
                }
                
                // Start the new property
                mappedProperty.start()
            },
            valueDidChange: {
                notify.valueDidChange()
            }
        ))
    }

    deinit {
        underlyingRemoval()
        mappedRemoval?()
    }
    
    fileprivate override func start() {
        print("BOOL STARTING")
        underlying.start()
        startInitial?()
        startInitial = nil
        super.start()
    }
}

private class BinaryOpValueProperty<T>: AsyncReadableProperty<T> {
    private let underlying1: AsyncPropertyType
    private let underlying2: AsyncPropertyType
    
    init<LHS: AsyncReadablePropertyType, RHS: AsyncReadablePropertyType>(_ lhs: LHS, _ rhs: RHS, _ f: @escaping (LHS.Value, RHS.Value) -> T)
        where LHS.Value == LHS.SignalChange, RHS.Value == RHS.SignalChange
    {
        self.underlying1 = lhs
        self.underlying2 = rhs
        
        let initialValue: T?
        if let l = lhs.value, let r = rhs.value {
            initialValue = f(l, r)
        } else {
            initialValue = nil
        }
        super.init(initialValue: initialValue, signal: BinaryOpSignal(lhs.signal, rhs.signal, f))
    }
    
    fileprivate override func start() {
        underlying1.start()
        underlying2.start()
        super.start()
    }
}
