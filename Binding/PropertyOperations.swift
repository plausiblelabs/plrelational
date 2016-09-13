//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

extension ReadablePropertyType {
    /// Returns a ReadableProperty whose value is derived from this property's `value`.
    /// The given `transform` will be applied whenever this property's value changes.
    public func map<U>(_ transform: @escaping (Self.Value) -> U) -> ReadableProperty<U> {
        return MappedValueProperty(property: self, transform: transform, valueChanging: valueChanging)
    }
    
    /// Returns a ReadableProperty whose value is derived from this property's `value`.
    /// The given `transform` will be applied whenever this property's value changes.
    public func map<U: Equatable>(_ transform: @escaping (Self.Value) -> U) -> ReadableProperty<U> {
        return MappedValueProperty(property: self, transform: transform, valueChanging: valueChanging)
    }
}

/// Returns a ReadableProperty whose value is a tuple (pair) containing the `value` from
/// each of the given properties.  The returned property's `value` will contain a fresh tuple
/// any time the value of either input changes.
public func zip<LHS: ReadablePropertyType, RHS: ReadablePropertyType>(_ lhs: LHS, _ rhs: RHS) -> ReadableProperty<(LHS.Value, RHS.Value)> {
    return BinaryOpValueProperty(lhs, rhs, { ($0, $1) }, valueChanging)
}

/// Returns a ReadableProperty whose value is the negation of the boolean value of the given property.
public func not<P: ReadablePropertyType>(_ property: P) -> ReadableProperty<Bool> where P.Value == Bool {
    return property.map{ !$0 }
}

extension ReadablePropertyType where Value == Bool {
    /// Returns a ReadableProperty whose value resolves to `self.value || other.value`.  The returned
    /// property's value will be recomputed any time the value of either input changes.
    public func or(_ other: Self) -> ReadableProperty<Bool> {
        return BinaryOpValueProperty(self, other, { $0 || $1 }, valueChanging)
    }
    
    /// Returns a ReadableProperty whose value resolves to `self.value && other.value`.  The returned
    /// property's value will be recomputed any time the value of either input changes.
    public func and(_ other: Self) -> ReadableProperty<Bool> {
        return BinaryOpValueProperty(self, other, { $0 && $1 }, valueChanging)
    }
    
    /// Returns a ReadableProperty that invokes the given function whenever this property's
    /// value resolves to `true`.
    public func then(_ f: @escaping () -> Void) -> ReadableProperty<()> {
        return MappedValueProperty(
            property: self,
            transform: { if $0 { f() } },
            valueChanging: { _ in false }
        )
    }
}

extension MutableValueProperty where T: ExpressibleByBooleanLiteral & Equatable {
    public func toggle(transient: Bool) {
        let newValue = value == false // dumb equivalent to !value for the protocol constraints
        self.change(newValue as! T, transient: transient)
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

public func *||<P: ReadablePropertyType>(lhs: P, rhs: P) -> ReadableProperty<Bool> where P.Value == Bool {
    return lhs.or(rhs)
}

public func *&&<P: ReadablePropertyType>(lhs: P, rhs: P) -> ReadableProperty<Bool> where P.Value == Bool {
    return lhs.and(rhs)
}

infix operator *== {
    associativity none
    precedence 130
}

public func *==<P: ReadablePropertyType>(lhs: P, rhs: P) -> ReadableProperty<Bool> where P.Value: Equatable {
    return BinaryOpValueProperty(lhs, rhs, { $0 == $1 }, valueChanging)
}

extension Sequence where Iterator.Element: ReadablePropertyType, Iterator.Element.Value == Bool {
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

extension ReadablePropertyType where Value: Sequence, Value.Iterator.Element: Hashable {
    /// Returns a ReadableProperty whose value resolves to a CommonValue that describes this
    /// property's sequence.
    public func common() -> ReadableProperty<CommonValue<Value.Iterator.Element>> {
        return CommonValueProperty(property: self)
    }
}

private class MappedValueProperty<T>: ReadableProperty<T> {
    fileprivate var removal: ObserverRemoval!
    
    init<P: ReadablePropertyType>(property: P, transform: @escaping (P.Value) -> T, valueChanging: @escaping (T, T) -> Bool) {
        let (signal, notify) = Signal<T>.pipe()
        
        super.init(initialValue: transform(property.value), signal: signal, notify: notify, changing: valueChanging)
        
        self.removal = property.signal.observe(notify, { [weak self] _, metadata in
            self?.setValue(transform(property.value), metadata)
        })
    }
    
    deinit {
        removal()
    }
}

private class BinaryOpValueProperty<T>: ReadableProperty<T> {
    fileprivate var removal1: ObserverRemoval!
    fileprivate var removal2: ObserverRemoval!
    
    init<LHS: ReadablePropertyType, RHS: ReadablePropertyType>(_ lhs: LHS, _ rhs: RHS, _ f: @escaping (LHS.Value, RHS.Value) -> T, _ valueChanging: @escaping (T, T) -> Bool) {
        let (signal, notify) = Signal<T>.pipe()

        super.init(initialValue: f(lhs.value, rhs.value), signal: signal, notify: notify, changing: valueChanging)
        
        self.removal1 = lhs.signal.observe(notify, { [weak self] _, metadata in
            self?.setValue(f(lhs.value, rhs.value), metadata)
        })
        self.removal2 = rhs.signal.observe(notify, { [weak self] _, metadata in
            self?.setValue(f(lhs.value, rhs.value), metadata)
        })
    }
    
    deinit {
        removal1()
        removal2()
    }
}

private class AnyTrueValueProperty: ReadableProperty<Bool> {
    fileprivate var removals: [ObserverRemoval] = []
    
    init<S: Sequence>(properties: S) where S.Iterator.Element: ReadablePropertyType, S.Iterator.Element.Value == Bool {
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
            let removal = property.signal.observe(notify, { [weak self] _, metadata in
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
    fileprivate var removals: [ObserverRemoval] = []
    
    init<S: Sequence>(properties: S) where S.Iterator.Element: ReadablePropertyType, S.Iterator.Element.Value == Bool {
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
            let removal = property.signal.observe(notify, { [weak self] _, metadata in
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
    fileprivate var removals: [ObserverRemoval] = []
    
    init<S: Sequence>(properties: S) where S.Iterator.Element: ReadablePropertyType, S.Iterator.Element.Value == Bool {
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
            let removal = property.signal.observe(notify, { [weak self] _, metadata in
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

private class CommonValueProperty<T: Hashable>: ReadableProperty<CommonValue<T>> {
    fileprivate var removal: ObserverRemoval!
    
    init<S: Sequence, P: ReadablePropertyType>(property: P) where S.Iterator.Element == T, P.Value == S {
        let (signal, notify) = Signal<CommonValue<T>>.pipe()

        func commonValue() -> CommonValue<T> {
            let valuesSet = Set(property.value)
            switch valuesSet.count {
            case 0:
                return .none
            case 1:
                return .one(valuesSet.first!)
            default:
                return .multi
            }
        }
        
        super.init(initialValue: commonValue(), signal: signal, notify: notify, changing: valueChanging)
        
        self.removal = property.signal.observe(notify, { [weak self] _, metadata in
            self?.setValue(commonValue(), metadata)
        })
    }
    
    deinit {
        removal()
    }
}
