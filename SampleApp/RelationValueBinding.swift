//
//  RelationBinding.swift
//  Relational
//
//  Created by Chris Campbell on 5/21/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import libRelational

private class BaseRelationValueBinding<T>: ValueBinding<T> {
    private var removal: ObserverRemoval!
    
    init(relation: Relation, relationToValue: Relation -> T) {
        super.init(initialValue: relationToValue(relation))
        
        self.removal = relation.addChangeObserver({ [weak self] _ in
            guard let weakSelf = self else { return }
            let newValue = relationToValue(relation)
            if weakSelf.valueChanging(newValue) {
                weakSelf.setValue(newValue)
            }
        })
    }
    
    /// Overridden by subclasses.
    private func valueChanging(newValue: T) -> Bool {
        return true
    }
}

private class RelationValueBinding<T: Equatable>: BaseRelationValueBinding<T> {
    override init(relation: Relation, relationToValue: Relation -> T) {
        super.init(relation: relation, relationToValue: relationToValue)
    }

    private override func valueChanging(newValue: T) -> Bool {
        return newValue != self.value
    }
}

// XXX: This is necessary because Optionals do not automatically conform to the Equatable protocol,
// even though they do have a generic implementation of `==`.
private class RelationOptValueBinding<T: Equatable>: BaseRelationValueBinding<T?> {
    override init(relation: Relation, relationToValue: Relation -> T?) {
        super.init(relation: relation, relationToValue: relationToValue)
    }
    
    private override func valueChanging(newValue: T?) -> Bool {
        return newValue != self.value
    }
}

private class WhenNonEmptyBinding<T>: ValueBinding<T?> {
    private var removal: ObserverRemoval!
    
    init(relation: Relation, relationToValue: Relation -> T) {

        func evaluate() -> T? {
            if relation.isEmpty.ok == false {
                return relationToValue(relation)
            } else {
                return nil
            }
        }
        
        super.init(initialValue: evaluate())
        
        self.removal = relation.addChangeObserver({ [weak self] _ in
            guard let weakSelf = self else { return }
            
            // Only re-evaluate if the relation is going from empty to non-empty or vice versa
            if weakSelf.value == nil {
                if let newValue = evaluate() {
                    weakSelf.setValue(newValue)
                }
            } else {
                if relation.isEmpty.ok != false {
                    weakSelf.setValue(nil)
                }
            }
        })
    }
}

public struct RelationBidiConfig<T> {
    let snapshot: () -> ChangeLoggingDatabaseSnapshot
    let update: (newValue: T) -> Void
    let commit: (before: ChangeLoggingDatabaseSnapshot, newValue: T) -> Void
}

private class BaseRelationBidiValueBinding<T>: BidiValueBinding<T> {
    private let config: RelationBidiConfig<T>
    private var before: ChangeLoggingDatabaseSnapshot?
    private var selfInitiatedChange = false
    private var removal: ObserverRemoval!

    init(relation: Relation, config: RelationBidiConfig<T>, relationToValue: Relation -> T) {
        self.config = config

        super.init(initialValue: relationToValue(relation))
    
        self.removal = relation.addChangeObserver({ [weak self] _ in
            guard let weakSelf = self else { return }
            
            if weakSelf.selfInitiatedChange { return }
            
            let newValue = relationToValue(relation)
            if weakSelf.valueChanging(newValue) {
                weakSelf.setValue(newValue)
            }
        })
    }
    
    /// Overridden by subclasses.
    private func valueChanging(newValue: T) -> Bool {
        return true
    }
    
    private override func update(newValue: T) {
        selfInitiatedChange = true
        if before == nil {
            before = config.snapshot()
        }
        value = newValue
        config.update(newValue: newValue)
        selfInitiatedChange = false
    }
    
    private override func commit(newValue: T) {
        selfInitiatedChange = true
        if before == nil {
            before = config.snapshot()
        }
        value = newValue
        config.commit(before: before!, newValue: newValue)
        self.before = nil
        selfInitiatedChange = false
    }
}

private class RelationBidiValueBinding<T: Equatable>: BaseRelationBidiValueBinding<T> {
    override init(relation: Relation, config: RelationBidiConfig<T>, relationToValue: Relation -> T) {
        super.init(relation: relation, config: config, relationToValue: relationToValue)
    }
    
    private override func valueChanging(newValue: T) -> Bool {
        return newValue != self.value
    }
}

// XXX: This is necessary because Optionals do not automatically conform to the Equatable protocol,
// even though they do have a generic implementation of `==`.
private class RelationBidiOptValueBinding<T: Equatable>: BaseRelationBidiValueBinding<T?> {
    override init(relation: Relation, config: RelationBidiConfig<T?>, relationToValue: Relation -> T?) {
        super.init(relation: relation, config: config, relationToValue: relationToValue)
    }
    
    private override func valueChanging(newValue: T?) -> Bool {
        return newValue != self.value
    }
}

extension Relation {
    /// Resolves to a set of all values for the single attribute, built from one transformed value for each non-error row.
    func allValues<V: Hashable>(transform: RelationValue -> V?) -> Set<V> {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        return Set(self.rows()
            .flatMap{$0.ok}
            .flatMap{transform($0[attr])})
    }
    
    /// Resolves to a set of all RelationValues for the single attribute.
    var allValues: Set<RelationValue> {
        return allValues{ $0 }
    }
    
    /// Resolves to some transformed value for the single attribute if there are one or more rows, or nil
    /// if there are no non-error rows.
    func anyValue<V>(transform: RelationValue -> V?) -> V? {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        if let row = self.rows().next()?.ok {
            return transform(row[attr])
        } else {
            return nil
        }
    }
    
    /// Resolves to some RelationValue for the single attribute if there are one or more rows, or nil
    /// if there are no non-error rows.
    var anyValue: RelationValue? {
        return anyValue{ $0 }
    }
    
    /// Resolves to a single transformed value if there is exactly one row in the relation, otherwise resolves
    /// to nil.
    func oneValue<V>(transform: RelationValue -> V?) -> V? {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        let rows = self.rows()
        if let row = rows.next()?.ok {
            if rows.next() == nil {
                return transform(row[attr])
            } else {
                return nil
            }
        } else {
            return nil
        }
    }
    
    /// Resolves to a single RelationValue if there is exactly one row in the relation, otherwise resolves
    /// to nil.
    var oneValue: RelationValue? {
        return oneValue{ $0 }
    }

    /// Resolves to a single string value if there is exactly one row in the relation, otherwise resolves
    /// to an empty string.
    var oneString: String {
        return oneValue{ $0.get() } ?? ""
    }

    /// Resolves to a single integer value if there is exactly one row in the relation, otherwise resolves
    /// to zero.
    var oneInteger: Int64 {
        return oneValue{ $0.get() } ?? 0
    }

    /// Resolves to a single boolean value if there is exactly one row in the relation, otherwise resolves
    /// to nil.
    var oneBool: Bool? {
        return oneValue{ $0.boolValue }
    }
}

extension Relation {
    /// Returns a read-only binding that gets its value from this relation.
    func bind<V: Equatable>(relationToValue: Relation -> V) -> ValueBinding<V> {
        return RelationValueBinding(relation: self, relationToValue: relationToValue)
    }

    /// Returns a read-only binding that gets its (optional) value from this relation.
    func bindOpt<V: Equatable>(relationToValue: Relation -> V?) -> ValueBinding<V?> {
        return RelationOptValueBinding(relation: self, relationToValue: relationToValue)
    }

    /// Returns a read-only binding that resolves to a set of all values for the single attribute.
    func bindAllValues<V: Hashable>(transform: RelationValue -> V?) -> ValueBinding<Set<V>> {
        return RelationValueBinding(relation: self, relationToValue: { $0.allValues(transform) })
    }

    /// Returns a read-only binding that resolves to some value for the single attribute, or nil if there are
    /// no non-error rows.
    func bindAnyValue<V: Equatable>(transform: RelationValue -> V?) -> ValueBinding<V?> {
        return RelationOptValueBinding(relation: self, relationToValue: { $0.anyValue(transform) })
    }

    /// Returns a read-only binding that resolves to a single value if there is exactly one row in the relation,
    /// otherwise resolves to nil.
    func bindOneValue<V: Equatable>(transform: RelationValue -> V?) -> ValueBinding<V?> {
        return RelationOptValueBinding(relation: self, relationToValue: { $0.oneValue(transform) })
    }

    /// Returns a bidirectional binding that gets its value from this relation and writes values back
    /// according to the provided bidi configuration.
    func bindBidi<V: Equatable>(config: RelationBidiConfig<V>, relationToValue: Relation -> V) -> BidiValueBinding<V> {
        return RelationBidiValueBinding(relation: self, config: config, relationToValue: relationToValue)
    }
    
    /// Returns a bidirectional binding that gets its (optional) value from this relation and writes values back
    /// according to the provided bidi configuration.
    func bindOptBidi<V: Equatable>(config: RelationBidiConfig<V?>, relationToValue: Relation -> V?) -> BidiValueBinding<V?> {
        return RelationBidiOptValueBinding(relation: self, config: config, relationToValue: relationToValue)
    }
}

extension Relation {
    /// A read-only binding that resolves to `true` if there are zero rows in the relation.
    var empty: ValueBinding<Bool> {
        return RelationValueBinding(relation: self, relationToValue: { $0.isEmpty.ok == true })
    }
    
    /// A read-only binding that resolves to `true` if there are one or more rows in the relation.
    var nonEmpty: ValueBinding<Bool> {
        return RelationValueBinding(relation: self, relationToValue: { $0.isEmpty.ok == false })
    }
    
    /// Returns a read-only binding that resolves to an optional value, which is nil when this
    /// relation is empty and is reconstructed when this relation becomes non-empty.
    func whenNonEmpty<V>(relationToValue: Relation -> V) -> ValueBinding<V?> {
        return WhenNonEmptyBinding(relation: self, relationToValue: relationToValue)
    }
    
    /// Returns a read-only binding that resolves to the given string value if there are multiple string
    /// values in the relation, otherwise resolves to the alternate string.
    func stringWhenMulti(string: String, otherwise: String = "") -> ValueBinding<String> {
        // TODO: Reimplement in terms of other bindings
        return RelationValueBinding(relation: self, relationToValue: { relation -> String in
            let values = self.allValues{ value -> String? in value.get() }
            if values.count > 1 {
                return string
            } else {
                return otherwise
            }
        })
    }
}

extension Relation {
    /// Performs an update using a single RelationValue.
    func updateValue(value: RelationValue) {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        let row: Row = [attr: value]
        var mutableRelation = self
        mutableRelation.update(true, newValues: row)
    }

    /// Performs an update using a single string value.
    func updateString(value: String) {
        updateValue(RelationValue(value))
    }

    /// Performs an update using a single optional string value.
    func updateNullableString(value: String?) {
        let rv: RelationValue
        if let value = value {
            rv = RelationValue(value)
        } else {
            rv = .NULL
        }
        updateValue(rv)
    }

    /// Performs an update using a single integer value.
    func updateInteger(value: Int64) {
        updateValue(RelationValue(value))
    }
    
    /// Performs an update using a single boolean value (converted to 0 for `false` and 1 for `true`).
    func updateBoolean(value: Bool) {
        updateValue(RelationValue(Int64(value ? 1 : 0)))
    }
}

extension MutableRelation {
    /// Replaces the given values by performing a delete followed by an add for each value.
    func replaceValues(values: [RelationValue]) {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        var mutableRelation = self
        mutableRelation.delete(true)
        for id in values {
            mutableRelation.add([attr: id])
        }
    }
}
