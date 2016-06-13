//
//  ObservableValue.swift
//  Relational
//
//  Created by Chris Campbell on 5/23/16.
//  Copyright © 2016 mikeash. All rights reserved.
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
    public typealias Changes = Void
    public typealias ChangeObserver = ChangeMetadata -> Void
    
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
    
    internal func notifyChangeObservers(metadata: ChangeMetadata) {
        for (_, f) in changeObservers {
            f(metadata)
        }
    }
    
    internal func setValue(value: T, _ metadata: ChangeMetadata) {
        if changing(self.value, value) {
            self.value = value
            self.notifyChangeObservers(metadata)
        }
    }
    
    // For testing purposes only.
    internal var observerCount: Int { return changeObservers.count }
}

extension ObservableValue {
    public static func constant(value: T) -> ObservableValue<T> {
        return ConstantObservableValue(value: value)
    }
    
    public func map<U>(transform: (T) -> U) -> ObservableValue<U> {
        return MappedObservableValue(binding: self, transform: transform, valueChanging: valueChanging)
    }

    public func map<U: Equatable>(transform: (T) -> U) -> ObservableValue<U> {
        return MappedObservableValue(binding: self, transform: transform, valueChanging: valueChanging)
    }

    public func zip<U>(other: ObservableValue<U>) -> ObservableValue<(T, U)> {
        return ZippedObservableValue(self, other)
    }
}

extension ObservableValue where T: SequenceType, T.Generator.Element: Hashable {
    public func common() -> ObservableValue<CommonValue<T.Generator.Element>> {
        return CommonObservableValue(binding: self)
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
    
    init<U>(binding: ObservableValue<U>, transform: (U) -> T, valueChanging: (T, T) -> Bool) {
        super.init(initialValue: transform(binding.value), valueChanging: valueChanging)
        self.removal = binding.addChangeObserver({ [weak self] metadata in
            self?.setValue(transform(binding.value), metadata)
        })
    }
}

private class ZippedObservableValue<U, V>: ObservableValue<(U, V)> {
    private var removal1: ObserverRemoval!
    private var removal2: ObserverRemoval!
    
    init(_ binding1: ObservableValue<U>, _ binding2: ObservableValue<V>) {
        super.init(initialValue: (binding1.value, binding2.value))
        self.removal1 = binding1.addChangeObserver({ [weak self] metadata in
            self?.setValue((binding1.value, binding2.value), metadata)
        })
        self.removal2 = binding2.addChangeObserver({ [weak self] metadata in
            self?.setValue((binding1.value, binding2.value), metadata)
        })
    }
}

private class CommonObservableValue<T: Hashable>: ObservableValue<CommonValue<T>> {
    private var removal: ObserverRemoval!
    
    init<S: SequenceType where S.Generator.Element == T>(binding: ObservableValue<S>) {
        
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
        
        self.removal = binding.addChangeObserver({ [weak self] metadata in
            self?.setValue(commonValue(), metadata)
        })
    }
}

public class BidiObservableValue<T>: ObservableValue<T> {
    public override init(initialValue: T, valueChanging: (T, T) -> Bool) {
        super.init(initialValue: initialValue, valueChanging: valueChanging)
    }
    
    public func update(newValue: T, _ metadata: ChangeMetadata) {
        setValue(newValue, metadata)
    }
}

public func bidiObservableValue<T: Equatable>(initialValue: T) -> BidiObservableValue<T> {
    return BidiObservableValue(initialValue: initialValue, valueChanging: valueChanging)
}

public func bidiObservableValue<T: Equatable>(initialValue: T?) -> BidiObservableValue<T?> {
    return BidiObservableValue(initialValue: initialValue, valueChanging: valueChanging)
}

extension BidiObservableValue where T: Equatable {
    public convenience init(_ initialValue: T) {
        self.init(initialValue: initialValue, valueChanging: valueChanging)
    }
}

extension BidiObservableValue where T: BooleanType {
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
