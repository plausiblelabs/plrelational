//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

extension ReadablePropertyType {
    /// Returns a ReadableProperty whose value is derived from this property's `value`.
    /// The given `transform` will be applied whenever this property's value changes.
    public func map<U>(_ transform: @escaping (Self.Value) -> U) -> ReadableProperty<U> {
        return ReadableProperty(signal: self.signal.map(transform), changing: valueChanging)
    }
    
    /// Returns a ReadableProperty whose value is derived from this property's `value`.
    /// The given `transform` will be applied whenever this property's value changes.
    public func map<U: Equatable>(_ transform: @escaping (Self.Value) -> U) -> ReadableProperty<U> {
        return ReadableProperty(signal: self.signal.map(transform), changing: valueChanging)
    }
}

//extension ReadWriteProperty {
//    public func bidiMap<U: Equatable>(forward: @escaping (T) -> U?, reverse: @escaping (U?) -> T) -> ReadWriteProperty<U?> {
//        let newProperty = mutableValueProperty(forward(self.value), valueChanging: { $0 != $1 })
//        _ = self.connectBidi(newProperty, forward: { .change(forward($0)) }, reverse: { .change(reverse($0)) })
//        return newProperty
//    }
//    
//    public func bidiMap<U: Equatable>(forward: @escaping (T) -> U, reverse: @escaping (U) -> T) -> ReadWriteProperty<U> {
//        let newProperty = mutableValueProperty(forward(self.value))
//        _ = self.connectBidi(newProperty, forward: { .change(forward($0)) }, reverse: { .change(reverse($0)) })
//        return newProperty
//    }
//}

/// Returns a ReadableProperty whose value is a tuple (pair) containing the `value` from
/// each of the given properties.  The returned property's `value` will contain a fresh tuple
/// any time the value of either input changes.
public func zip<LHS: ReadablePropertyType, RHS: ReadablePropertyType>(_ lhs: LHS, _ rhs: RHS) -> ReadableProperty<(LHS.Value, RHS.Value)> {
    return ReadableProperty(signal: zip(lhs.signal, rhs.signal), changing: valueChanging)
}

/// Returns a ReadableProperty whose value is the negation of the boolean value of the given property.
public func not<P: ReadablePropertyType>(_ property: P) -> ReadableProperty<Bool> where P.Value == Bool {
    return property.map{ !$0 }
}

extension ReadablePropertyType where Value == Bool {
    /// Returns a ReadableProperty whose value resolves to `self.value || other.value`.  The returned
    /// property's value will be recomputed any time the value of either input changes.
    public func or(_ other: Self) -> ReadableProperty<Bool> {
        return ReadableProperty(signal: self.signal *|| other.signal, changing: valueChanging)
    }
    
    /// Returns a ReadableProperty whose value resolves to `self.value && other.value`.  The returned
    /// property's value will be recomputed any time the value of either input changes.
    public func and(_ other: Self) -> ReadableProperty<Bool> {
        return ReadableProperty(signal: self.signal *&& other.signal, changing: valueChanging)
    }
}

extension MutableValueProperty where T == Bool {
    public func toggle(transient: Bool) {
        let newValue = !self.value
        self.change(newValue, transient: transient)
    }
}

// TODO: This syntax is same as SelectExpression operators; maybe we should use something different
infix operator *||: LogicalDisjunctionPrecedence

infix operator *&& : LogicalConjunctionPrecedence

public func *||<P: ReadablePropertyType>(lhs: P, rhs: P) -> ReadableProperty<Bool> where P.Value == Bool {
    return lhs.or(rhs)
}

public func *&&<P: ReadablePropertyType>(lhs: P, rhs: P) -> ReadableProperty<Bool> where P.Value == Bool {
    return lhs.and(rhs)
}

infix operator *== : ComparisonPrecedence

public func *==<P: ReadablePropertyType>(lhs: P, rhs: P) -> ReadableProperty<Bool> where P.Value: Equatable {
    return ReadableProperty(signal: lhs.signal *== rhs.signal, changing: valueChanging)
}
