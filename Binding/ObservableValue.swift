//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

public struct ChangeMetadata {
    public let transient: Bool
    
    public init(transient: Bool) {
        self.transient = transient
    }
}

public class ObservableValue<T>: Observable {
    public typealias Value = T
    public typealias Changes = Value
    public typealias ChangeObserver = (Value, ChangeMetadata) -> Void
    
    internal(set) public var value: T
    internal let changing: (T, T) -> Bool
    internal let signal: Signal<T>
    private let notify: Signal<T>.Notify
    
    public init(initialValue: T, valueChanging: (T, T) -> Bool = valueChanging) {
        self.value = initialValue
        self.changing = valueChanging
        (self.signal, self.notify) = Signal.pipe()
    }

    // TODO: Remove this in favor of making `signal` public?
    public func addChangeObserver(observer: ChangeObserver) -> ObserverRemoval {
        return signal.observe(observer)
    }
    
    internal func setValue(value: T, _ metadata: ChangeMetadata) {
        if changing(self.value, value) {
            self.value = value
            notify(newValue: value, metadata: metadata)
        }
    }
    
    // For testing purposes only.
    internal var observerCount: Int { return signal.observerCount }
}

extension ObservableValue {
    /// Returns an ObservableValue whose value never changes.  Note that since the value cannot change,
    /// observers will never be notified of changes.
    public static func constant(value: T) -> ObservableValue<T> {
        return ConstantObservableValue(value: value)
    }
    
    /// Returns an ObservableValue whose value is derived from this ObservableValue's `value`.
    /// The given `transform` will be applied whenever this ObservableValue`s value changes.
    public func map<U>(transform: (T) -> U) -> ObservableValue<U> {
        return MappedObservableValue(observable: self, transform: transform, valueChanging: valueChanging)
    }

    /// Returns an ObservableValue whose value is derived from this ObservableValue's `value`.
    /// The given `transform` will be applied whenever this ObservableValue`s value changes.
    public func map<U: Equatable>(transform: (T) -> U) -> ObservableValue<U> {
        return MappedObservableValue(observable: self, transform: transform, valueChanging: valueChanging)
    }
}

/// Returns an ObservableValue whose value is a tuple (pair) containing the `value` from
/// each of the given ObservableValues.  The returned ObservableValue's `value` will
/// contain a fresh tuple any time the value of either input changes.
public func zip<T, U>(lhs: ObservableValue<T>, _ rhs: ObservableValue<U>) -> ObservableValue<(T, U)> {
    return BinaryOpObservableValue(lhs, rhs, { ($0, $1) }, valueChanging)
}

/// Returns an ObservableValue whose value is the negation of the boolean value of the given observable.
public func not<T: BooleanType>(observable: ObservableValue<T>) -> ObservableValue<Bool> {
    return observable.map{ !$0.boolValue }
}

extension ObservableValue where T: BooleanType {
    /// Returns an ObservableValue whose value resolves to `self.value || other.value`.  The returned
    /// ObservableValue's `value` will be recomputed any time the value of either input changes.
    public func or(other: ObservableValue<T>) -> ObservableValue<Bool> {
        return BinaryOpObservableValue(self, other, { $0.boolValue || $1.boolValue }, valueChanging)
    }
    
    /// Returns an ObservableValue whose value resolves to `self.value && other.value`.  The returned
    /// ObservableValue's `value` will be recomputed any time the value of either input changes.
    public func and(other: ObservableValue<T>) -> ObservableValue<Bool> {
        return BinaryOpObservableValue(self, other, { $0.boolValue && $1.boolValue }, valueChanging)
    }
    
    /// Returns an ObservableValue that invokes the given function whenever this ObservableValue's
    /// `value` resolves to `true`.
    public func then(f: () -> Void) -> ObservableValue<()> {
        return ThenObservableValue(self, f)
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

public func *||<T: BooleanType>(lhs: ObservableValue<T>, rhs: ObservableValue<T>) -> ObservableValue<Bool> {
    return lhs.or(rhs)
}

public func *&&<T: BooleanType>(lhs: ObservableValue<T>, rhs: ObservableValue<T>) -> ObservableValue<Bool> {
    return lhs.and(rhs)
}

infix operator *== {
    associativity none
    precedence 130
}

public func *==<T: Equatable>(lhs: ObservableValue<T>, rhs: ObservableValue<T>) -> ObservableValue<Bool> {
    return BinaryOpObservableValue(lhs, rhs, { $0 == $1 }, valueChanging)
}

extension SequenceType where Generator.Element == ObservableValue<Bool> {
    /// Returns an ObservableValue whose value resolves to `true` if *any* of the ObservableValues
    /// in this sequence resolve to `true`.
    public func anyTrue() -> ObservableValue<Bool> {
        return AnyTrueObservableValue(observables: self)
    }
    
    /// Returns an ObservableValue whose value resolves to `true` if *all* of the ObservableValues
    /// in this sequence resolve to `true`.
    public func allTrue() -> ObservableValue<Bool> {
        return AllTrueObservableValue(observables: self)
    }
    
    /// Returns an ObservableValue whose value resolves to `true` if *none* of the ObservableValues
    /// in this sequence resolve to `true`.
    public func noneTrue() -> ObservableValue<Bool> {
        return NoneTrueObservableValue(observables: self)
    }
}

extension ObservableValue where T: SequenceType, T.Generator.Element: Hashable {
    /// Returns an ObservableValue whose value resolves to a CommonValue that describes this
    /// ObservableValue's sequence value.
    public func common() -> ObservableValue<CommonValue<T.Generator.Element>> {
        return CommonObservableValue(observable: self)
    }
}

private class ConstantObservableValue<T>: ObservableValue<T> {
    init(value: T) {
        super.init(initialValue: value)
    }
    
    private override func addChangeObserver(observer: ChangeObserver) -> ObserverRemoval {
        return {}
    }
}

private class MappedObservableValue<T>: ObservableValue<T> {
    private var removal: ObserverRemoval!
    
    init<U>(observable: ObservableValue<U>, transform: (U) -> T, valueChanging: (T, T) -> Bool) {
        super.init(initialValue: transform(observable.value), valueChanging: valueChanging)
        self.removal = observable.addChangeObserver({ [weak self] newValue, metadata in
            self?.setValue(transform(observable.value), metadata)
        })
    }
    
    deinit {
        removal()
    }
}

private class BinaryOpObservableValue<T>: ObservableValue<T> {
    private var removal1: ObserverRemoval!
    private var removal2: ObserverRemoval!
    
    init<U, V>(_ observable1: ObservableValue<U>, _ observable2: ObservableValue<V>, _ f: (U, V) -> T, _ valueChanging: (T, T) -> Bool) {
        super.init(initialValue: f(observable1.value, observable2.value), valueChanging: valueChanging)
        
        self.removal1 = observable1.addChangeObserver({ [weak self] _, metadata in
            self?.setValue(f(observable1.value, observable2.value), metadata)
        })
        
        self.removal2 = observable2.addChangeObserver({ [weak self] _, metadata in
            self?.setValue(f(observable1.value, observable2.value), metadata)
        })
    }
    
    deinit {
        removal1()
        removal2()
    }
}

private class ThenObservableValue: ObservableValue<()> {
    private var removal: ObserverRemoval!
    
    init<B: BooleanType>(_ observable: ObservableValue<B>, _ f: () -> Void) {
        super.init(initialValue: (), valueChanging: { _ in false })
        self.removal = observable.addChangeObserver({ _ in
            if observable.value.boolValue {
                f()
            }
        })
    }
    
    deinit {
        removal()
    }
}

private class AnyTrueObservableValue: ObservableValue<Bool> {
    private var removals: [ObserverRemoval] = []
    
    init<B: BooleanType, S: SequenceType where S.Generator.Element == ObservableValue<B>>(observables: S) {
        
        func anyTrue() -> Bool {
            for observable in observables {
                if observable.value {
                    return true
                }
            }
            return false
        }
        
        super.init(initialValue: anyTrue(), valueChanging: valueChanging)
        
        for observable in observables {
            let removal = observable.addChangeObserver({ [weak self] _, metadata in
                let newValue = observable.value
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

private class AllTrueObservableValue: ObservableValue<Bool> {
    private var removals: [ObserverRemoval] = []
    
    init<B: BooleanType, S: SequenceType where S.Generator.Element == ObservableValue<B>>(observables: S) {
        // TODO: Require at least one element?

        func allTrue() -> Bool {
            for observable in observables {
                if !observable.value {
                    return false
                }
            }
            return true
        }
        
        super.init(initialValue: allTrue(), valueChanging: valueChanging)
        
        for observable in observables {
            let removal = observable.addChangeObserver({ [weak self] _, metadata in
                let newValue = observable.value
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

private class NoneTrueObservableValue: ObservableValue<Bool> {
    private var removals: [ObserverRemoval] = []
    
    init<B: BooleanType, S: SequenceType where S.Generator.Element == ObservableValue<B>>(observables: S) {
        
        func noneTrue() -> Bool {
            for observable in observables {
                if observable.value {
                    return false
                }
            }
            return true
        }
        
        super.init(initialValue: noneTrue(), valueChanging: valueChanging)
        
        for observable in observables {
            let removal = observable.addChangeObserver({ [weak self] _, metadata in
                let newValue = observable.value
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

private class CommonObservableValue<T: Hashable>: ObservableValue<CommonValue<T>> {
    private var removal: ObserverRemoval!
    
    init<S: SequenceType where S.Generator.Element == T>(observable: ObservableValue<S>) {
        
        func commonValue() -> CommonValue<T> {
            let valuesSet = Set(observable.value)
            switch valuesSet.count {
            case 0:
                return .None
            case 1:
                return .One(valuesSet.first!)
            default:
                return .Multi
            }
        }
        
        super.init(initialValue: commonValue())
        
        self.removal = observable.addChangeObserver({ [weak self] _, metadata in
            self?.setValue(commonValue(), metadata)
        })
    }
    
    deinit {
        removal()
    }
}

public class MutableObservableValue<T>: ObservableValue<T> {
    internal override init(initialValue: T, valueChanging: (T, T) -> Bool) {
        super.init(initialValue: initialValue, valueChanging: valueChanging)
    }
    
    public func update(newValue: T, _ metadata: ChangeMetadata) {
        setValue(newValue, metadata)
    }
}

public func mutableObservableValue<T>(initialValue: T, valueChanging: (T, T) -> Bool) -> MutableObservableValue<T> {
    return MutableObservableValue(initialValue: initialValue, valueChanging: valueChanging)
}

public func mutableObservableValue<T: Equatable>(initialValue: T) -> MutableObservableValue<T> {
    return MutableObservableValue(initialValue: initialValue, valueChanging: valueChanging)
}

public func mutableObservableValue<T: Equatable>(initialValue: T?) -> MutableObservableValue<T?> {
    return MutableObservableValue(initialValue: initialValue, valueChanging: valueChanging)
}

extension MutableObservableValue where T: BooleanType {
    public func toggle(metadata: ChangeMetadata = ChangeMetadata(transient: true)) {
        let newValue = !value
        update(newValue as! T, metadata)
    }
}

internal func valueChanging<T>(v0: T, v1: T) -> Bool {
    return true
}

internal func valueChanging<T: Equatable>(v0: T, v1: T) -> Bool {
    return v0 != v1
}

internal func valueChanging<T>(v0: T?, v1: T?) -> Bool {
    return true
}

internal func valueChanging<T: Equatable>(v0: T?, v1: T?) -> Bool {
    return v0 != v1
}
