//
//  Binding.swift
//  Relational
//
//  Created by Chris Campbell on 5/3/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Foundation
import libRelational

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

public class ConcreteValueBinding<T: Equatable>: ValueBinding<T?> {
    private let relation: Relation
    private let attribute: Attribute
    private var removal: ObserverRemoval!
    private var selfInitiatedChange = false
    
    init(relation: Relation, unwrap: (RelationValue) -> T?) {
        precondition(relation.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        
        self.relation = relation
        self.attribute = relation.scheme.attributes.first!
        super.init(initialValue: ConcreteValueBinding.getValue(relation, attribute).flatMap(unwrap))
        self.removal = relation.addChangeObserver({ [weak self] _ in
            guard let weakSelf = self else { return }
            
            if weakSelf.selfInitiatedChange { return }
            
            let newValue = ConcreteValueBinding.getValue(relation, weakSelf.attribute).flatMap(unwrap)
            if newValue != weakSelf.value {
                weakSelf.value = newValue
                weakSelf.notifyChangeObservers()
            }
        })
    }

    private static func getValue(relation: Relation, _ attribute: Attribute) -> RelationValue? {
        if let row = relation.rows().next()?.ok {
            return row[attribute]
        } else {
            return nil
        }
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

public struct BidiChange<T> {
    let f: (newValue: T, oldValue: T, commit: Bool) -> Void
}

public class StringBidiBinding: StringBinding {
    private let change: BidiChange<String>
    
    init(relation: Relation, change: BidiChange<String>) {
        self.change = change
        super.init(relation: relation)
    }

    public func change(newValue newValue: String, oldValue: String) {
        selfInitiatedChange = true
        self.value = newValue
        change.f(newValue: newValue, oldValue: oldValue, commit: false)
        selfInitiatedChange = false
    }
    
    public func commit(newValue newValue: String, oldValue: String) {
        selfInitiatedChange = true
        self.value = newValue
        change.f(newValue: newValue, oldValue: oldValue, commit: true)
        selfInitiatedChange = false
    }
}
