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
    
    internal typealias ChangeObserver = Void -> Void
    internal typealias ObserverRemoval = Void -> Void
    
    internal(set) public var value: T
    private var changeObservers: [UInt64: (Void -> Void)] = [:]
    private var changeObserverNextID: UInt64 = 0
    
    init(initialValue: T) {
        self.value = initialValue
    }
    
    public func addChangeObserver(observer: Void -> Void) -> (Void -> Void) {
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
        // TODO: Don't notify if value is not actually changing
        self.value = value
        self.notifyChangeObservers()
    }
}

extension ValueBinding {
    public func map<U>(transform: (T) -> U) -> ValueBinding<U> {
        return MappedValueBinding(binding: self, transform: transform)
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

private class MappedValueBinding<T>: ValueBinding<T> {
    private var removal: ObserverRemoval!
    
    init<U>(binding: ValueBinding<U>, transform: (U) -> T) {
        super.init(initialValue: transform(binding.value))
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

// XXX: Hmm, this requires a subclass implementation; lousy design
public class BidiValueBinding<T>: ValueBinding<T> {
    override init(initialValue: T) {
        super.init(initialValue: initialValue)
    }
    
    public func update(newValue: T) {
    }
    
    public func commit(newValue: T) {
    }
}
