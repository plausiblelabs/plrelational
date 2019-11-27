//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

extension ReadablePropertyType {
    
    // MARK: Operations
    
    /// Returns a ReadableProperty whose value is derived from this property's `value`.
    /// The given `transform` will be applied whenever this property's value changes.
    public func map<U>(_ transform: @escaping (Self.Value) -> U) -> ReadableProperty<U> {
        return UnaryOpProperty(signal: self.signal.map(transform), changing: valueChanging, owner: self)
    }
    
    /// Returns a ReadableProperty whose value is derived from this property's `value`.
    /// The given `transform` will be applied whenever this property's value changes.
    public func map<U: Equatable>(_ transform: @escaping (Self.Value) -> U) -> ReadableProperty<U> {
        return UnaryOpProperty(signal: self.signal.map(transform), changing: valueChanging, owner: self)
    }
    
    /// Returns a ReadableProperty with the same type and value. Useful for hiding the
    /// original property type.
    public var readable: ReadableProperty<Value> {
        return self.map({ $0 })
    }
}

extension ReadWriteProperty {
    /// Returns a ReadWriteProperty that supports bidirectional transformation of the underlying value.
    ///
    /// - parameter outgoing: The transformation to apply when the underlying value is changing (going "out" to another property).
    /// - parameter incoming: The transformation to apply when a new value is coming "in" from another property.
    public func mapBidi<U: Equatable>(outgoing: @escaping (T) -> U, incoming: @escaping (U) -> T) -> ReadWriteProperty<U> {
        // Make the new property take on the transformed version of the underlying property's value
        let newProperty = mutableValueProperty(outgoing(self.value))

        // Set up a bidirectional transformation
        // TODO: Should we hold onto this underlying Binding?
        _ = self.connectBidi(
            newProperty,
            leftToRight: { value, _ in
                .change(outgoing(value))
            },
            rightToLeft: { value, _ in
                .change(incoming(value))
            }
        )
    
        return newProperty
    }
}

/// Returns a ReadableProperty whose value is a tuple (pair) containing the `value` from
/// each of the given properties.  The returned property's `value` will contain a fresh tuple
/// any time the value of either input changes.
public func zip<LHS: ReadablePropertyType, RHS: ReadablePropertyType>(_ lhs: LHS, _ rhs: RHS) -> ReadableProperty<(LHS.Value, RHS.Value)> {
    return BinaryOpProperty(signal: zip(lhs.signal, rhs.signal), changing: valueChanging, owner1: lhs, owner2: rhs)
}

/// Returns a ReadableProperty whose value is the negation of the boolean value of the given property.
public func not<P: ReadablePropertyType>(_ property: P) -> ReadableProperty<Bool> where P.Value == Bool {
    return property.map{ !$0 }
}

extension ReadablePropertyType where Value == Bool {
    /// Returns a ReadableProperty whose value resolves to `self.value || other.value`.  The returned
    /// property's value will be recomputed any time the value of either input changes.
    public func or<P: ReadablePropertyType>(_ other: P) -> ReadableProperty<Bool> where P.Value == Bool {
        return BinaryOpProperty(signal: self.signal *|| other.signal, changing: valueChanging, owner1: self, owner2: other)
    }
    
    /// Returns a ReadableProperty whose value resolves to `self.value && other.value`.  The returned
    /// property's value will be recomputed any time the value of either input changes.
    public func and<P: ReadablePropertyType>(_ other: P) -> ReadableProperty<Bool> where P.Value == Bool {
        return BinaryOpProperty(signal: self.signal *&& other.signal, changing: valueChanging, owner1: self, owner2: other)
    }
}

extension MutableValueProperty where T == Bool {
    
    // MARK: Operations
    
    public func toggle(transient: Bool) {
        let newValue = !self.value
        self.change(newValue, transient: transient)
    }
}

// TODO: This syntax is same as SelectExpression operators; maybe we should use something different
infix operator *||: LogicalDisjunctionPrecedence

infix operator *&& : LogicalConjunctionPrecedence

public func *||<LHS: ReadablePropertyType, RHS: ReadablePropertyType>(lhs: LHS, rhs: RHS) -> ReadableProperty<Bool> where LHS.Value == Bool, RHS.Value == Bool {
    return lhs.or(rhs)
}

public func *&&<LHS: ReadablePropertyType, RHS: ReadablePropertyType>(lhs: LHS, rhs: RHS) -> ReadableProperty<Bool> where LHS.Value == Bool, RHS.Value == Bool {
    return lhs.and(rhs)
}

infix operator *== : ComparisonPrecedence

public func *==<LHS: ReadablePropertyType, RHS: ReadablePropertyType>(lhs: LHS, rhs: RHS) -> ReadableProperty<Bool> where LHS.Value: Equatable, LHS.Value == RHS.Value {
    return BinaryOpProperty(signal: lhs.signal *== rhs.signal, changing: valueChanging, owner1: lhs, owner2: rhs)
}

/// Property that keeps a strong reference to the signal owner.
private class UnaryOpProperty<T>: ReadableProperty<T> {
    
    private let owner: AnyObject
    
    init(signal: Signal<T>, changing: @escaping (T, T) -> Bool, owner: AnyObject) {
        self.owner = owner
        super.init(signal: signal, changing: changing)
    }
}

/// Property that keeps a strong reference to the signal owners.
private class BinaryOpProperty<T>: ReadableProperty<T> {
    
    private let owner1: AnyObject
    private let owner2: AnyObject
    
    init(signal: Signal<T>, changing: @escaping (T, T) -> Bool, owner1: AnyObject, owner2: AnyObject) {
        self.owner1 = owner1
        self.owner2 = owner2
        super.init(signal: signal, changing: changing)
    }
}
