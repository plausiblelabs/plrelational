//
//  Binding.swift
//  Relational
//
//  Created by Chris Campbell on 5/3/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Foundation
import libRelational

enum CommonValue<T> { case
    /// The value is not defined for any item.
    None,
    
    /// The value is the same for all items.
    One(T),
    
    /// There is a mixed set of values across all items.
    Multi
    
    /// Returns the single value if there is one, or the given default value in the .None or .Multi cases.
    func orDefault(defaultValue: T) -> T {
        switch self {
        case .None, .Multi:
            return defaultValue
        case .One(let value):
            return value
        }
    }
    
    /// Returns the single value if there is one, or nil in the .None or .Multi cases.
    func orNil() -> T? {
        switch self {
        case .None, .Multi:
            return nil
        case .One(let value):
            return value
        }
    }
}

extension CommonValue where T: Equatable {
    /// Returns true if all items share the given value.
    func all(value: T) -> Bool {
        switch self {
        case let .One(v):
            return v == value
        default:
            return false
        }
    }
}

public class ValueBinding<T> {
    
    public typealias ChangeObserver = Void -> Void
    public typealias ObserverRemoval = Void -> Void
    
    private(set) public var value: T
    private var changeObservers: [UInt64: ChangeObserver] = [:]
    private var changeObserverNextID: UInt64 = 0

    init(initialValue: T) {
        self.value = initialValue
    }
    
    public func addChangeObserver(observer: ChangeObserver) -> ObserverRemoval {
        let id = changeObserverNextID
        changeObserverNextID += 1
        changeObservers[id] = observer
        return { self.changeObservers.removeValueForKey(id) }
    }
    
    private func notifyChangeObservers() {
        for (_, f) in changeObservers {
            f()
        }
    }
}

extension ValueBinding {
    func map<U>(transform: (T) -> U) -> ValueBinding<U> {
        return MappedValueBinding(binding: self, transform: transform)
    }
    
    func zip<U>(other: ValueBinding<U>) -> ValueBinding<(T, U)> {
        return ZippedValueBinding(self, other)
    }
}

extension ValueBinding where T: SequenceType, T.Generator.Element: Hashable {
    func common() -> ValueBinding<CommonValue<T.Generator.Element>> {
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

public class ZippedValueBinding<U, V>: ValueBinding<(U, V)> {
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

public class ExistsBinding: ValueBinding<Bool> {
    private let relation: Relation
    private var removal: ObserverRemoval!
    
    init(relation: Relation) {
        self.relation = relation
        // TODO: Need to see if the row result is OK
        super.init(initialValue: relation.rows().next() != nil)
        self.removal = relation.addChangeObserver({ [weak self] _ in
            guard let weakSelf = self else { return }
            let newValue = relation.rows().next() != nil
            if newValue != weakSelf.value {
                weakSelf.value = newValue
                weakSelf.notifyChangeObservers()
            }
        })
    }
}

public class NotExistsBinding: ValueBinding<Bool> {
    private let relation: Relation
    private var removal: ObserverRemoval!
    
    init(relation: Relation) {
        self.relation = relation
        super.init(initialValue: relation.rows().next() == nil)
        self.removal = relation.addChangeObserver({ [weak self] _ in
            guard let weakSelf = self else { return }
            let newValue = relation.rows().next() == nil
            if newValue != weakSelf.value {
                weakSelf.value = newValue
                weakSelf.notifyChangeObservers()
            }
        })
    }
}

public class CommonValueBinding<T: Hashable>: ValueBinding<CommonValue<T>> {
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

public class SingleRowBinding: ValueBinding<Row?> {
    private let relation: Relation
    private var removal: ObserverRemoval!
    
    init(relation: Relation) {
        self.relation = relation
        
        func matchingRow() -> Row? {
            return relation.rows().next()?.ok
        }
        
        super.init(initialValue: matchingRow())
        self.removal = relation.addChangeObserver({ [weak self] _ in
            guard let weakSelf = self else { return }
            let newValue = matchingRow()
            weakSelf.value = newValue
            weakSelf.notifyChangeObservers()
        })
    }
}

public class MultiRowBinding: ValueBinding<[Row]> {
    private let relation: Relation
    private var removal: ObserverRemoval!
    
    init(relation: Relation) {
        self.relation = relation
        
        func allRows() -> [Row] {
            return relation.rows().flatMap{$0.ok}
        }
        
        super.init(initialValue: allRows())
        self.removal = relation.addChangeObserver({ [weak self] _ in
            guard let weakSelf = self else { return }
            let newValue = allRows()
            weakSelf.value = newValue
            weakSelf.notifyChangeObservers()
        })
    }
}

public class ConcreteValueBinding<T: Equatable>: ValueBinding<T?> {
    private let relation: Relation
    private var removal: ObserverRemoval!
    private var selfInitiatedChange = false
    
    init(relation: Relation, unwrap: (RelationValue) -> T?) {
        precondition(relation.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attribute = relation.scheme.attributes.first!
        
        func getValue() -> RelationValue? {
            if let row = relation.rows().next()?.ok {
                return row[attribute]
            } else {
                return nil
            }
        }
        
        self.relation = relation
        super.init(initialValue: getValue().flatMap(unwrap))
        
        self.removal = relation.addChangeObserver({ [weak self] _ in
            guard let weakSelf = self else { return }
            
            if weakSelf.selfInitiatedChange { return }
            
            let newValue = getValue().flatMap(unwrap)
            if newValue != weakSelf.value {
                weakSelf.value = newValue
                weakSelf.notifyChangeObservers()
            }
        })
    }
}

public class RelationValueBinding: ConcreteValueBinding<RelationValue> {
    init(relation: Relation) {
        super.init(relation: relation, unwrap: { $0 })
    }
}

public class StringBinding: ConcreteValueBinding<String> {
    init(relation: Relation) {
        super.init(relation: relation, unwrap: { $0.get() })
    }
}

public class Int64Binding: ConcreteValueBinding<Int64> {
    init(relation: Relation) {
        super.init(relation: relation, unwrap: { $0.get() })
    }
}

public class ConcreteMultiValueBinding<T: Equatable>: ValueBinding<[T]> {
    private let relation: Relation
    private var removal: ObserverRemoval!
    private var selfInitiatedChange = false
    
    init(relation: Relation, unwrap: (RelationValue) -> T?) {
        precondition(relation.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attribute = relation.scheme.attributes.first!
        
        func getValues() -> [RelationValue] {
            // TODO: Error handling
            var values: [RelationValue] = []
            for row in relation.rows() {
                switch row {
                case .Ok(let row):
                    values.append(row[attribute])
                case .Err:
                    // TODO: Error handling
                    break
                }
            }
            return values
        }
        
        self.relation = relation
        super.init(initialValue: getValues().flatMap(unwrap))
        
        self.removal = relation.addChangeObserver({ [weak self] _ in
            guard let weakSelf = self else { return }
            
            if weakSelf.selfInitiatedChange { return }
            
            let newValues = getValues().flatMap(unwrap)
            if newValues != weakSelf.value {
                weakSelf.value = newValues
                weakSelf.notifyChangeObservers()
            }
        })
    }
}

public class MultiRelationValueBinding: ConcreteMultiValueBinding<RelationValue> {
    init(relation: Relation) {
        super.init(relation: relation, unwrap: { $0 })
    }
}

public class MultiStringBinding: ConcreteMultiValueBinding<String> {
    init(relation: Relation) {
        super.init(relation: relation, unwrap: { $0.get() })
    }
}

public class MultiInt64Binding: ConcreteMultiValueBinding<Int64> {
    init(relation: Relation) {
        super.init(relation: relation, unwrap: { $0.get() })
    }
}

public class StringBidiBinding: StringBinding {
    
    typealias Snapshot = () -> ChangeLoggingDatabaseSnapshot
    typealias Change = (newValue: String) -> Void
    typealias Commit = (before: ChangeLoggingDatabaseSnapshot, newValue: String) -> Void
    
    private let snapshot: Snapshot
    private let change: Change
    private let commit: Commit
    private var before: ChangeLoggingDatabaseSnapshot?

    init(relation: Relation, snapshot: Snapshot, change: Change, commit: Commit) {
        self.snapshot = snapshot
        self.change = change
        self.commit = commit
        super.init(relation: relation)
    }

    public func change(newValue: String) {
        selfInitiatedChange = true
        if before == nil {
            self.before = snapshot()
        }
        self.value = newValue
        self.change(newValue: newValue)
        selfInitiatedChange = false
    }
    
    public func commit(newValue: String) {
        selfInitiatedChange = true
        self.value = newValue
        if let before = before {
            self.commit(before: before, newValue: newValue)
            self.before = nil
        }
        selfInitiatedChange = false
    }
}
