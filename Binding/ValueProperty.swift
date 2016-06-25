//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

private class ConstantValueProperty<T>: ReadableProperty<T> {
    private init(_ value: T) {
        // TODO: Use a no-op signal here
        let (signal, notify) = Signal<T>.pipe()
        super.init(initialValue: value, signal: signal, notify: notify, changing: { _ in false })
    }
}

/// Returns a ValueProperty whose value never changes.  Note that since the value cannot change,
/// observers will never be notified of changes.
public func constantValueProperty<T>(value: T) -> ReadableProperty<T> {
    return ConstantValueProperty(value)
}

public class MutableValueProperty<T>: ReadWriteProperty<T> {

    public let change: (T, transient: Bool) -> Void

    private init(_ initialValue: T, valueChanging: (T, T) -> Bool, didSet: Setter?) {
        let (signal, notify) = Signal<T>.pipe()

        var value = initialValue

        change = { (newValue: T, transient: Bool) in
            if valueChanging(value, newValue) {
                value = newValue
                notify(newValue: newValue, metadata: ChangeMetadata(transient: transient))
            }
        }

        super.init(
            get: {
                value
            },
            set: { newValue, metadata in
                if valueChanging(value, newValue) {
                    value = newValue
                    didSet?(newValue, metadata)
                    notify(newValue: newValue, metadata: metadata)
                }
            },
            signal: signal,
            notify: notify
        )
    }
}

public func mutableValueProperty<T>(initialValue: T, valueChanging: (T, T) -> Bool) -> MutableValueProperty<T> {
    return MutableValueProperty(initialValue, valueChanging: valueChanging, didSet: nil)
}

public func mutableValueProperty<T: Equatable>(initialValue: T) -> MutableValueProperty<T> {
    return MutableValueProperty(initialValue, valueChanging: valueChanging, didSet: nil)
}

public func mutableValueProperty<T: Equatable>(initialValue: T?) -> MutableValueProperty<T?> {
    return MutableValueProperty(initialValue, valueChanging: valueChanging, didSet: nil)
}

extension ReadablePropertyType {
    /// Returns a ReadableProperty whose value is derived from this property's `value`.
    /// The given `transform` will be applied whenever this property's value changes.
    public func map<U>(transform: Self.Value -> U) -> ReadableProperty<U> {
        return MappedValueProperty(property: self, transform: transform, valueChanging: valueChanging)
    }
    
    /// Returns a ReadableProperty whose value is derived from this property's `value`.
    /// The given `transform` will be applied whenever this property's value changes.
    public func map<U: Equatable>(transform: Self.Value -> U) -> ReadableProperty<U> {
        return MappedValueProperty(property: self, transform: transform, valueChanging: valueChanging)
    }
}

/// Returns a ReadableProperty whose value is a tuple (pair) containing the `value` from
/// each of the given properties.  The returned property's `value` will contain a fresh tuple
/// any time the value of either input changes.
public func zip<LHS: ReadablePropertyType, RHS: ReadablePropertyType>(lhs: LHS, _ rhs: RHS) -> ReadableProperty<(LHS.Value, RHS.Value)> {
    return BinaryOpValueProperty(lhs, rhs, { ($0, $1) }, valueChanging)
}

/// Returns a ReadableProperty whose value is the negation of the boolean value of the given property.
public func not<P: ReadablePropertyType where P.Value: BooleanType>(property: P) -> ReadableProperty<Bool> {
    return property.map{ !$0.boolValue }
}

extension ReadablePropertyType where Value: BooleanType {
    /// Returns a ReadableProperty whose value resolves to `self.value || other.value`.  The returned
    /// property's value will be recomputed any time the value of either input changes.
    public func or(other: Self) -> ReadableProperty<Bool> {
        return BinaryOpValueProperty(self, other, { $0.boolValue || $1.boolValue }, valueChanging)
    }
    
    /// Returns a ReadableProperty whose value resolves to `self.value && other.value`.  The returned
    /// property's value will be recomputed any time the value of either input changes.
    public func and(other: Self) -> ReadableProperty<Bool> {
        return BinaryOpValueProperty(self, other, { $0.boolValue && $1.boolValue }, valueChanging)
    }
    
    /// Returns a ReadableProperty that invokes the given function whenever this property's
    /// value resolves to `true`.
    public func then(f: () -> Void) -> ReadableProperty<()> {
        return MappedValueProperty(
            property: self,
            transform: { if $0.boolValue { f() } },
            valueChanging: { _ in false }
        )
    }
}

// TODO: This syntax is same as SelectExpression operators; maybe we should use something different
infix operator *|| {
    associativity left
    precedence 110
}

infix operator *&& {
    associativity left
    precedence 120
}

public func *||<P: ReadablePropertyType where P.Value: BooleanType>(lhs: P, rhs: P) -> ReadableProperty<Bool> {
    return lhs.or(rhs)
}

public func *&&<P: ReadablePropertyType where P.Value: BooleanType>(lhs: P, rhs: P) -> ReadableProperty<Bool> {
    return lhs.and(rhs)
}

infix operator *== {
    associativity none
    precedence 130
}

public func *==<P: ReadablePropertyType where P.Value: Equatable>(lhs: P, rhs: P) -> ReadableProperty<Bool> {
    return BinaryOpValueProperty(lhs, rhs, { $0 == $1 }, valueChanging)
}

extension SequenceType where Generator.Element: ReadablePropertyType, Generator.Element.Value: BooleanType {
    /// Returns a ReadableProperty whose value resolves to `true` if *any* of the properties
    /// in this sequence resolve to `true`.
    public func anyTrue() -> ReadableProperty<Bool> {
        return AnyTrueValueProperty(properties: self)
    }
    
    /// Returns a ReadableProperty whose value resolves to `true` if *all* of the properties
    /// in this sequence resolve to `true`.
    public func allTrue() -> ReadableProperty<Bool> {
        return AllTrueValueProperty(properties: self)
    }
    
    /// Returns a ValueProperty whose value resolves to `true` if *none* of the properties
    /// in this sequence resolve to `true`.
    public func noneTrue() -> ReadableProperty<Bool> {
        return NoneTrueValueProperty(properties: self)
    }
}

private class MappedValueProperty<T>: ReadableProperty<T> {
    private var removal: ObserverRemoval!
    
    init<P: ReadablePropertyType>(property: P, transform: (P.Value) -> T, valueChanging: (T, T) -> Bool) {
        let (signal, notify) = Signal<T>.pipe()
        
        super.init(initialValue: transform(property.value), signal: signal, notify: notify, changing: valueChanging)
        
        self.removal = property.signal.observe({ [weak self] _, metadata in
            self?.setValue(transform(property.value), metadata)
        })
    }
    
    deinit {
        removal()
    }
}

private class BinaryOpValueProperty<T>: ReadableProperty<T> {
    private var removal1: ObserverRemoval!
    private var removal2: ObserverRemoval!
    
    init<LHS: ReadablePropertyType, RHS: ReadablePropertyType>(_ lhs: LHS, _ rhs: RHS, _ f: (LHS.Value, RHS.Value) -> T, _ valueChanging: (T, T) -> Bool) {
        let (signal, notify) = Signal<T>.pipe()

        super.init(initialValue: f(lhs.value, rhs.value), signal: signal, notify: notify, changing: valueChanging)
        
        self.removal1 = lhs.signal.observe({ [weak self] _, metadata in
            self?.setValue(f(lhs.value, rhs.value), metadata)
        })
        self.removal2 = rhs.signal.observe({ [weak self] _, metadata in
            self?.setValue(f(lhs.value, rhs.value), metadata)
        })
    }
    
    deinit {
        removal1()
        removal2()
    }
}

private class AnyTrueValueProperty: ReadableProperty<Bool> {
    private var removals: [ObserverRemoval] = []
    
    init<S: SequenceType where S.Generator.Element: ReadablePropertyType, S.Generator.Element.Value: BooleanType>(properties: S) {
        let (signal, notify) = Signal<Bool>.pipe()

        func anyTrue() -> Bool {
            for property in properties {
                if property.value {
                    return true
                }
            }
            return false
        }
        
        super.init(initialValue: anyTrue(), signal: signal, notify: notify, changing: valueChanging)
        
        for property in properties {
            let removal = property.signal.observe({ [weak self] _, metadata in
                let newValue = property.value
                if newValue {
                    self?.setValue(true, metadata)
                } else {
                    self?.setValue(anyTrue(), metadata)
                }
            })
            removals.append(removal)
        }
    }
    
    deinit {
        removals.forEach{ $0() }
    }
}

private class AllTrueValueProperty: ReadableProperty<Bool> {
    private var removals: [ObserverRemoval] = []
    
    init<S: SequenceType where S.Generator.Element: ReadablePropertyType, S.Generator.Element.Value: BooleanType>(properties: S) {
        // TODO: Require at least one element?
        let (signal, notify) = Signal<Bool>.pipe()

        func allTrue() -> Bool {
            for property in properties {
                if !property.value {
                    return false
                }
            }
            return true
        }
        
        super.init(initialValue: allTrue(), signal: signal, notify: notify, changing: valueChanging)
        
        for property in properties {
            let removal = property.signal.observe({ [weak self] _, metadata in
                let newValue = property.value
                if !newValue {
                    self?.setValue(false, metadata)
                } else {
                    self?.setValue(allTrue(), metadata)
                }
            })
            removals.append(removal)
        }
    }
    
    deinit {
        removals.forEach{ $0() }
    }
}

private class NoneTrueValueProperty: ReadableProperty<Bool> {
    private var removals: [ObserverRemoval] = []
    
    init<S: SequenceType where S.Generator.Element: ReadablePropertyType, S.Generator.Element.Value: BooleanType>(properties: S) {
        let (signal, notify) = Signal<Bool>.pipe()

        func noneTrue() -> Bool {
            for property in properties {
                if property.value {
                    return false
                }
            }
            return true
        }
        
        super.init(initialValue: noneTrue(), signal: signal, notify: notify, changing: valueChanging)
        
        for property in properties {
            let removal = property.signal.observe({ [weak self] _, metadata in
                let newValue = property.value
                if newValue {
                    self?.setValue(false, metadata)
                } else {
                    self?.setValue(noneTrue(), metadata)
                }
            })
            removals.append(removal)
        }
    }
    
    deinit {
        removals.forEach{ $0() }
    }
}
