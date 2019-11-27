//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

extension ReadablePropertyType {
    
    // MARK: Convert to async
    
    /// Returns an AsyncReadableProperty that is derived from this synchronous property's signal.
    public func async() -> AsyncReadableProperty<Value> {
        return UnaryOpProperty(signal: self.signal, underlyingProperty: self)
    }
}

extension AsyncReadablePropertyType where Self.Value == Self.SignalChange {
    
    // MARK: Operations
    
    /// Returns an AsyncReadableProperty whose value is derived from this property's `value`.
    /// The given `transform` will be applied whenever this property's value changes.
    public func map<U>(_ transform: @escaping (Self.Value) -> U) -> AsyncReadableProperty<U> {
        return UnaryOpProperty(signal: self.signal.map(transform), underlyingProperty: self)
    }
    
    /// Returns an AsyncReadableProperty whose value is derived from the given property's `value`.
    /// The given `transform` will be applied whenever this property's value changes, and in turn
    /// the property returned by `transform` becomes the new source of values.
    public func flatMap<P: AsyncReadablePropertyType>(_ transform: @escaping (Self.Value) -> P) -> AsyncReadableProperty<P.Value>
        where P.Value == P.SignalChange
    {
        return FlatMappedProperty(signal: self.signal, transform: transform, underlyingProperty: self)
    }
}

/// Returns an AsyncReadableProperty whose value is a tuple (pair) containing the `value` from
/// each of the given properties.  The returned property's `value` will contain a fresh tuple
/// any time the value of either input changes.
public func zip<LHS: AsyncReadablePropertyType, RHS: AsyncReadablePropertyType>(_ lhs: LHS, _ rhs: RHS) -> AsyncReadableProperty<(LHS.Value, RHS.Value)>
    where LHS.Value == LHS.SignalChange, RHS.Value == RHS.SignalChange
{
    return BinaryOpProperty(signal: zip(lhs.signal, rhs.signal), underlyingProperty1: lhs, underlyingProperty2: rhs)
}

/// Returns an AsyncReadableProperty whose value is the negation of the boolean value of the given property.
public func not<P: AsyncReadablePropertyType>(_ property: P) -> AsyncReadableProperty<Bool>
    where P.Value == Bool, P.SignalChange == Bool
{
    return property.map{ !$0 }
}

prefix operator !

/// Returns an AsyncReadableProperty whose value is the negation of the given boolean property.
public prefix func !<P: AsyncReadablePropertyType>(property: P) -> AsyncReadableProperty<Bool>
    where P.Value == Bool, P.SignalChange == Bool
{
    return not(property)
}

/// Property that keeps a strong reference to the signal owner.
private class UnaryOpProperty<T>: AsyncReadableProperty<T> {
    
    private let underlyingProperty: AnyObject
    
    init(signal: Signal<T>, underlyingProperty: AnyObject) {
        self.underlyingProperty = underlyingProperty
        super.init(signal: signal)
    }
}

/// Property that keeps a strong reference to the signal owners.
private class BinaryOpProperty<T>: AsyncReadableProperty<T> {
    
    private let underlyingProperty1: AnyObject
    private let underlyingProperty2: AnyObject
    
    init(signal: Signal<T>, underlyingProperty1: AnyObject, underlyingProperty2: AnyObject) {
        self.underlyingProperty1 = underlyingProperty1
        self.underlyingProperty2 = underlyingProperty2
        super.init(signal: signal)
    }
}

// XXX: The purpose of this custom subclass is to keep a strong reference to the latest AsyncReadableProperty
// that is returned by `transform`.  Due to the way AsyncReadableProperty weakly/lazily observes its underlying
// signal, the mapped signal would be dead in the case where no one else is strongly holding onto its parent
// property.  The whole question of property/signal/binding lifetimes needs to be rethought.
private class FlatMappedProperty<T, U>: AsyncReadableProperty<U> {
    
    private let underlyingProperty: AnyObject
    private var mappedProperty: AsyncReadableProperty<U>?
    
    init<P: AsyncReadablePropertyType>(signal: Signal<T>, transform: @escaping (T) -> P, underlyingProperty: AnyObject) where P.Value == U, P.SignalChange == U {
        self.underlyingProperty = underlyingProperty
        
        let delegatingSignal = DelegatingSignal<U>()
        
        super.init(signal: delegatingSignal)

        delegatingSignal.underlyingSignal = signal.flatMap{ [weak self] (newValue: T) -> Signal<U> in
            let mappedProperty: AsyncReadableProperty<U> = transform(newValue).property
            self?.mappedProperty = mappedProperty
            return mappedProperty.signal
        }
    }
}
