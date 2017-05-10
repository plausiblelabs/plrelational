//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

extension AsyncReadablePropertyType where Self.Value == Self.SignalChange {
    /// Returns an AsyncReadableProperty whose value is derived from this property's `value`.
    /// The given `transform` will be applied whenever this property's value changes.
    public func map<U>(_ transform: @escaping (Self.Value) -> U) -> AsyncReadableProperty<U> {
        return AsyncReadableProperty(signal: self.signal.map(transform))
    }
    
    /// Returns an AsyncReadableProperty whose value is derived from the given property's `value`.
    /// The given `transform` will be applied whenever this property's value changes, and in turn
    /// the property returned by `transform` becomes the new source of values.
    public func flatMap<P: AsyncReadablePropertyType>(_ transform: @escaping (Self.Value) -> P) -> AsyncReadableProperty<P.Value>
        where P.Value == P.SignalChange
    {
        return AsyncReadableProperty(signal: self.signal.flatMap{
            return transform($0).signal
        })
    }
}

/// Returns an AsyncReadableProperty whose value is a tuple (pair) containing the `value` from
/// each of the given properties.  The returned property's `value` will contain a fresh tuple
/// any time the value of either input changes.
public func zip<LHS: AsyncReadablePropertyType, RHS: AsyncReadablePropertyType>(_ lhs: LHS, _ rhs: RHS) -> AsyncReadableProperty<(LHS.Value, RHS.Value)>
    where LHS.Value == LHS.SignalChange, RHS.Value == RHS.SignalChange
{
    return AsyncReadableProperty(signal: zip(lhs.signal, rhs.signal))
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
