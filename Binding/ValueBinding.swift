//
//  ValueBinding.swift
//  Relational
//
//  Created by Chris Campbell on 5/23/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Foundation

public class ValueBinding<T>: Binding {
    public typealias Value = T
    public typealias Changes = Void
    public typealias ChangeObserver = Changes -> Void
    
    internal(set) public var value: T
    internal let changing: (T, T) -> Bool
    private var changeObservers: [UInt64: ChangeObserver] = [:]
    private var changeObserverNextID: UInt64 = 0
    
    public init(initialValue: T, valueChanging: (T, T) -> Bool = valueChanging) {
        self.value = initialValue
        self.changing = valueChanging
    }
    
    public func addChangeObserver(observer: ChangeObserver) -> ObserverRemoval {
        let id = changeObserverNextID
        changeObserverNextID += 1
        changeObservers[id] = observer
        return { self.changeObservers.removeValueForKey(id) }
    }
    
    internal func notifyChangeObservers() {
        for (_, f) in changeObservers {
            f()
        }
    }
    
    internal func setValue(value: T) {
        if changing(self.value, value) {
            self.value = value
            self.notifyChangeObservers()
        }
    }
    
    // For testing purposes only.
    internal var observerCount: Int { return changeObservers.count }
}

extension ValueBinding {
    public static func constant(value: T) -> ValueBinding<T> {
        return ConstantValueBinding(value: value)
    }
    
    public func map<U>(transform: (T) -> U) -> ValueBinding<U> {
        return MappedValueBinding(binding: self, transform: transform, valueChanging: valueChanging)
    }

    public func map<U: Equatable>(transform: (T) -> U) -> ValueBinding<U> {
        return MappedValueBinding(binding: self, transform: transform, valueChanging: valueChanging)
    }

    public func zip<U>(other: ValueBinding<U>) -> ValueBinding<(T, U)> {
        return ZippedValueBinding(self, other)
    }
}

extension ValueBinding where T: SequenceType, T.Generator.Element: Equatable {
    public func isOne(value: T.Generator.Element) -> ValueBinding<Bool> {
        return IsOneValueBinding(binding: self, value: value)
    }
}

extension ValueBinding where T: SequenceType, T.Generator.Element: Hashable {
    public func common() -> ValueBinding<CommonValue<T.Generator.Element>> {
        return CommonValueBinding(binding: self)
    }
}

private class ConstantValueBinding<T>: ValueBinding<T> {
    init(value: T) {
        super.init(initialValue: value)
    }
    
    private override func addChangeObserver(observer: ChangeObserver) -> ObserverRemoval {
        return {}
    }
}

private class MappedValueBinding<T>: ValueBinding<T> {
    private var removal: ObserverRemoval!
    
    init<U>(binding: ValueBinding<U>, transform: (U) -> T, valueChanging: (T, T) -> Bool) {
        super.init(initialValue: transform(binding.value), valueChanging: valueChanging)
        self.removal = binding.addChangeObserver({ [weak self] in
            self?.setValue(transform(binding.value))
        })
    }
}

private class ZippedValueBinding<U, V>: ValueBinding<(U, V)> {
    private var removal1: ObserverRemoval!
    private var removal2: ObserverRemoval!
    
    init(_ binding1: ValueBinding<U>, _ binding2: ValueBinding<V>) {
        super.init(initialValue: (binding1.value, binding2.value))
        self.removal1 = binding1.addChangeObserver({ [weak self] in
            self?.setValue((binding1.value, binding2.value))
        })
        self.removal2 = binding2.addChangeObserver({ [weak self] in
            self?.setValue((binding1.value, binding2.value))
        })
    }
}

private class IsOneValueBinding<T: Equatable>: ValueBinding<Bool> {
    private var removal: ObserverRemoval!
    
    init<S: SequenceType where S.Generator.Element == T>(binding: ValueBinding<S>, value: T) {
        
        func isOne() -> Bool {
            let values = Array(binding.value)
            return values.count == 1 && values.first! == value
        }
        
        super.init(initialValue: isOne())
        
        self.removal = binding.addChangeObserver({ [weak self] in
            self?.setValue(isOne())
        })
    }
}

private class CommonValueBinding<T: Hashable>: ValueBinding<CommonValue<T>> {
    private var removal: ObserverRemoval!
    
    init<S: SequenceType where S.Generator.Element == T>(binding: ValueBinding<S>) {
        
        func commonValue() -> CommonValue<T> {
            let valuesSet = Set(binding.value)
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
        
        self.removal = binding.addChangeObserver({ [weak self] in
            self?.setValue(commonValue())
        })
    }
}

public class BidiValueBinding<T>: ValueBinding<T> {
    public override init(initialValue: T, valueChanging: (T, T) -> Bool) {
        super.init(initialValue: initialValue, valueChanging: valueChanging)
    }
    
    public func update(newValue: T) {
        setValue(newValue)
    }
    
    public func commit(newValue: T) {
        setValue(newValue)
    }
}

public func bidiValueBinding<T: Equatable>(initialValue: T) -> BidiValueBinding<T> {
    return BidiValueBinding(initialValue: initialValue, valueChanging: valueChanging)
}

public func bidiValueBinding<T: Equatable>(initialValue: T?) -> BidiValueBinding<T?> {
    return BidiValueBinding(initialValue: initialValue, valueChanging: valueChanging)
}

extension BidiValueBinding where T: Equatable {
    public convenience init(_ initialValue: T) {
        self.init(initialValue: initialValue, valueChanging: valueChanging)
    }
}

extension BidiValueBinding where T: BooleanType {
    public func toggle() {
        let newValue = !value
        commit(newValue as! T)
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
