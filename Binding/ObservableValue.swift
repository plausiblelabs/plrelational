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
        return MappedObservableValue(observable: self, transform: transform, valueChanging: valueChanging)
    }

    public func map<U: Equatable>(transform: (T) -> U) -> ObservableValue<U> {
        return MappedObservableValue(observable: self, transform: transform, valueChanging: valueChanging)
    }

    public func zip<U>(other: ObservableValue<U>) -> ObservableValue<(T, U)> {
        return ZippedObservableValue(self, other)
    }
}

extension ObservableValue where T: SequenceType, T.Generator.Element: Hashable {
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
        self.removal = observable.addChangeObserver({ [weak self] metadata in
            self?.setValue(transform(observable.value), metadata)
        })
    }
}

private class ZippedObservableValue<U, V>: ObservableValue<(U, V)> {
    private var removal1: ObserverRemoval!
    private var removal2: ObserverRemoval!
    
    init(_ observable1: ObservableValue<U>, _ observable2: ObservableValue<V>) {
        super.init(initialValue: (observable1.value, observable2.value))
        self.removal1 = observable1.addChangeObserver({ [weak self] metadata in
            self?.setValue((observable1.value, observable2.value), metadata)
        })
        self.removal2 = observable2.addChangeObserver({ [weak self] metadata in
            self?.setValue((observable1.value, observable2.value), metadata)
        })
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
        
        self.removal = observable.addChangeObserver({ [weak self] metadata in
            self?.setValue(commonValue(), metadata)
        })
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
