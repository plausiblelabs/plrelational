//
//  Binding.swift
//  Relational
//
//  Created by Chris Campbell on 5/3/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Foundation

public protocol Binding {
    associatedtype Value
    associatedtype Change
    
    var value: Value { get }
    
    func addChangeObserver(observer: Change -> Void) -> (Void -> Void)
}

public class ValueBinding<T>: Binding {
    public typealias Value = T
    public typealias Change = Void
    
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
}

extension ValueBinding {
    public func map<U>(transform: (T) -> U) -> ValueBinding<U> {
        return MappedValueBinding(binding: self, transform: transform)
    }
    
    public func zip<U>(other: ValueBinding<U>) -> ValueBinding<(T, U)> {
        return ZippedValueBinding(self, other)
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
            guard let weakSelf = self else { return }
            // TODO: Don't notify if value is not actually changing
            weakSelf.value = transform(binding.value)
            weakSelf.notifyChangeObservers()
        })
    }
}

private class ZippedValueBinding<U, V>: ValueBinding<(U, V)> {
    private var removal1: ObserverRemoval!
    private var removal2: ObserverRemoval!

    init(_ binding1: ValueBinding<U>, _ binding2: ValueBinding<V>) {
        super.init(initialValue: (binding1.value, binding2.value))
        self.removal1 = binding1.addChangeObserver({ [weak self] in
            guard let weakSelf = self else { return }
            weakSelf.value = (binding1.value, binding2.value)
            weakSelf.notifyChangeObservers()
        })
        self.removal2 = binding2.addChangeObserver({ [weak self] in
            guard let weakSelf = self else { return }
            weakSelf.value = (binding1.value, binding2.value)
            weakSelf.notifyChangeObservers()
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
            guard let weakSelf = self else { return }
            let common = commonValue()
            // TODO: Don't notify if value is not actually changing
            //if common != weakSelf.value {
                weakSelf.value = common
                weakSelf.notifyChangeObservers()
            //}
        })
    }
}

//public class StringBidiBinding: StringBinding {
//    
//    typealias Snapshot = () -> ChangeLoggingDatabaseSnapshot
//    typealias Change = (newValue: String) -> Void
//    typealias Commit = (before: ChangeLoggingDatabaseSnapshot, newValue: String) -> Void
//    
//    private let snapshot: Snapshot
//    private let change: Change
//    private let commit: Commit
//    private var before: ChangeLoggingDatabaseSnapshot?
//
//    init(relation: Relation, snapshot: Snapshot, change: Change, commit: Commit) {
//        self.snapshot = snapshot
//        self.change = change
//        self.commit = commit
//        super.init(relation: relation)
//    }
//
//    public func change(newValue: String) {
//        selfInitiatedChange = true
//        if before == nil {
//            self.before = snapshot()
//        }
//        self.value = newValue
//        self.change(newValue: newValue)
//        selfInitiatedChange = false
//    }
//    
//    public func commit(newValue: String) {
//        selfInitiatedChange = true
//        self.value = newValue
//        if let before = before {
//            self.commit(before: before, newValue: newValue)
//            self.before = nil
//        }
//        selfInitiatedChange = false
//    }
//}

//public class BidiBinding<T>: ValueBinding<T> {
//
//    typealias Snapshot = () -> ChangeLoggingDatabaseSnapshot
//    typealias Change = (newValue: T) -> Void
//    typealias Commit = (before: ChangeLoggingDatabaseSnapshot, newValue: T) -> Void
//    
//    private let snapshot: Snapshot
//    private let change: Change
//    private let commit: Commit
//    
//    private var before: ChangeLoggingDatabaseSnapshot?
//    private var removal: ObserverRemoval!
//    private var selfInitiatedChange = false
//
//    init(binding: ValueBinding<T>, snapshot: Snapshot, change: Change, commit: Commit) {
//        self.snapshot = snapshot
//        self.change = change
//        self.commit = commit
//        
//        super.init(initialValue: binding.value)
//        
//        self.removal = binding.addChangeObserver({ [weak self] in
//            guard let weakSelf = self else { return }
//
//            if weakSelf.selfInitiatedChange { return }
//
//            // TODO: Don't notify if value is not actually changing
//            weakSelf.value = binding.value
//            weakSelf.notifyChangeObservers()
//        })
//    }
//
//    public func change(newValue: T) {
//        selfInitiatedChange = true
//        if before == nil {
//            self.before = snapshot()
//        }
//        self.value = newValue
//        self.change(newValue: newValue)
//        selfInitiatedChange = false
//    }
//    
//    public func commit(newValue: T) {
//        selfInitiatedChange = true
//        self.value = newValue
//        if let before = before {
//            self.commit(before: before, newValue: newValue)
//            self.before = nil
//        }
//        selfInitiatedChange = false
//    }
//}
