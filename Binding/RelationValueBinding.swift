//
//  RelationBinding.swift
//  Relational
//
//  Created by Chris Campbell on 5/21/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import libRelational

private class RelationValueBinding<T>: ValueBinding<T> {
    private var removal: ObserverRemoval!
    
    init(relation: Relation, relationToValue: Relation -> T, valueChanging: (T, T) -> Bool) {
        super.init(initialValue: relationToValue(relation), valueChanging: valueChanging)
        
        self.removal = relation.addChangeObserver({ [weak self] _ in
            guard let weakSelf = self else { return }
            let newValue = relationToValue(relation)
            weakSelf.setValue(newValue)
        })
    }
    
    deinit {
        removal()
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
    
    deinit {
        removal()
    }
}

public struct RelationBidiConfig<T> {
    public let snapshot: () -> ChangeLoggingDatabaseSnapshot
    public let update: (newValue: T) -> Void
    public let commit: (before: ChangeLoggingDatabaseSnapshot, newValue: T) -> Void
    
    public init(
        snapshot: () -> ChangeLoggingDatabaseSnapshot,
        update: (newValue: T) -> Void,
        commit: (before: ChangeLoggingDatabaseSnapshot, newValue: T) -> Void)
    {
        self.snapshot = snapshot
        self.update = update
        self.commit = commit
    }
}

private class RelationBidiValueBinding<T>: BidiValueBinding<T> {
    private let config: RelationBidiConfig<T>
    private var before: ChangeLoggingDatabaseSnapshot?
    private var selfInitiatedChange = false
    private var removal: ObserverRemoval!

    init(relation: Relation, config: RelationBidiConfig<T>, relationToValue: Relation -> T, valueChanging: (T, T) -> Bool) {
        self.config = config

        super.init(initialValue: relationToValue(relation), valueChanging: valueChanging)
    
        self.removal = relation.addChangeObserver({ [weak self] _ in
            guard let weakSelf = self else { return }

            // TODO: We need to manage this externally
            //if weakSelf.selfInitiatedChange { return }
            
            let newValue = relationToValue(relation)
            print("RELATION UPDATED: \(newValue)")
            weakSelf.setValue(newValue)
        })
    }
    
    deinit {
        removal()
    }
    
    private override func update(newValue: T) {
        if !changing(value, newValue) {
            return
        }
        
        //selfInitiatedChange = true
        if before == nil {
            before = config.snapshot()
        }
        // Note: We don't set self.value here; instead we wait to receive the change from the
        // relation in our change observer and then update the value there
        config.update(newValue: newValue)
        //selfInitiatedChange = false
    }
    
    private override func commit(newValue: T) {
        if !changing(value, newValue) {
            return
        }

        //selfInitiatedChange = true
        if before == nil {
            before = config.snapshot()
        }
        // Note: We don't set self.value here; instead we wait to receive the change from the
        // relation in our change observer and then update the value there
        config.commit(before: before!, newValue: newValue)
        self.before = nil
        //selfInitiatedChange = false
    }
}

extension Relation {
    /// Resolves to a set of all values for the single attribute, built from one transformed value for each non-error row.
    public func allValues<V: Hashable>(transform: RelationValue -> V?) -> Set<V> {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        return Set(self.rows()
            .flatMap{$0.ok}
            .flatMap{transform($0[attr])})
    }
    
    /// Resolves to a set of all RelationValues for the single attribute.
    public var allValues: Set<RelationValue> {
        return allValues{ $0 }
    }
    
    /// Resolves to some transformed value for the single attribute if there are one or more rows, or nil
    /// if there are no non-error rows.
    public func anyValue<V>(transform: RelationValue -> V?) -> V? {
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
    public var anyValue: RelationValue? {
        return anyValue{ $0 }
    }
    
    /// Resolves to a single transformed value if there is exactly one row in the relation, otherwise resolves
    /// to nil.
    public func oneValue<V>(transform: RelationValue -> V?) -> V? {
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
    public var oneValue: RelationValue? {
        return oneValue{ $0 }
    }

    /// Resolves to a single string value if there is exactly one row in the relation, otherwise resolves
    /// to an empty string.
    public var oneString: String {
        return oneValue{ $0.get() } ?? ""
    }

    /// Resolves to a single string value if there is exactly one row in the relation, otherwise resolves
    /// to nil.
    public var oneStringOrNil: String? {
        return oneValue{ $0.get() }
    }

    /// Resolves to a single integer value if there is exactly one row in the relation, otherwise resolves
    /// to zero.
    public var oneInteger: Int64 {
        return oneValue{ $0.get() } ?? 0
    }

    /// Resolves to a single integer value if there is exactly one row in the relation, otherwise resolves
    /// to nil.
    public var oneIntegerOrNil: Int64? {
        return oneValue{ $0.get() }
    }

    /// Resolves to a single boolean value if there is exactly one row in the relation, otherwise resolves
    /// to false.
    public var oneBool: Bool {
        return oneValue{ $0.boolValue } ?? false
    }

    /// Resolves to a single boolean value if there is exactly one row in the relation, otherwise resolves
    /// to nil.
    public var oneBoolOrNil: Bool? {
        return oneValue{ $0.boolValue }
    }
    
    /// Resolves to a CommonValue that indicates whether there are zero, one, or multiple rows in the relation.
    public func commonValue<V>(transform: RelationValue -> V?) -> CommonValue<V> {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        let rows = self.rows()
        if let row = rows.next()?.ok {
            if rows.next() == nil {
                if let value = transform(row[attr]) {
                    return .One(value)
                } else {
                    return .None
                }
            } else {
                return .Multi
            }
        } else {
            return .None
        }
    }
}

extension Relation {
    /// Returns a read-only binding that gets its value from this relation.
    public func bind<V>(relationToValue: Relation -> V) -> ValueBinding<V> {
        return RelationValueBinding(relation: self, relationToValue: relationToValue, valueChanging: valueChanging)
    }

    /// Returns a read-only binding that gets its value from this relation.
    public func bind<V: Equatable>(relationToValue: Relation -> V) -> ValueBinding<V> {
        return RelationValueBinding(relation: self, relationToValue: relationToValue, valueChanging: valueChanging)
    }

    /// Returns a read-only binding that gets its value from this relation.
    public func bind<V>(relationToValue: Relation -> V?) -> ValueBinding<V?> {
        return RelationValueBinding(relation: self, relationToValue: relationToValue, valueChanging: valueChanging)
    }

    /// Returns a read-only binding that gets its value from this relation.
    public func bind<V: Equatable>(relationToValue: Relation -> V?) -> ValueBinding<V?> {
        return RelationValueBinding(relation: self, relationToValue: relationToValue, valueChanging: valueChanging)
    }

    /// Returns a read-only binding that resolves to a set of all values for the single attribute.
    public func bindAllValues<V: Hashable>(transform: RelationValue -> V?) -> ValueBinding<Set<V>> {
        return bind{ $0.allValues(transform) }
    }

    /// Returns a read-only binding that resolves to some value for the single attribute, or nil if there are
    /// no non-error rows.
    public func bindAnyValue<V>(transform: RelationValue -> V?) -> ValueBinding<V?> {
        return bind{ $0.anyValue(transform) }
    }

    /// Returns a read-only binding that resolves to some value for the single attribute, or nil if there are
    /// no non-error rows.
    public func bindAnyValue<V: Equatable>(transform: RelationValue -> V?) -> ValueBinding<V?> {
        return bind{ $0.anyValue(transform) }
    }

    /// Returns a read-only binding that resolves to a single value if there is exactly one row in the relation,
    /// otherwise resolves to nil.
    public func bindOneValue<V>(transform: RelationValue -> V?) -> ValueBinding<V?> {
        return bind{ $0.oneValue(transform) }
    }

    /// Returns a read-only binding that resolves to a single value if there is exactly one row in the relation,
    /// otherwise resolves to nil.
    public func bindOneValue<V: Equatable>(transform: RelationValue -> V?) -> ValueBinding<V?> {
        return bind{ $0.oneValue(transform) }
    }

    /// Returns a bidirectional binding that gets its value from this relation and writes values back
    /// according to the provided bidi configuration.
    public func bindBidi<V>(config: RelationBidiConfig<V>, relationToValue: Relation -> V) -> BidiValueBinding<V> {
        return RelationBidiValueBinding(relation: self, config: config, relationToValue: relationToValue, valueChanging: valueChanging)
    }

    /// Returns a bidirectional binding that gets its value from this relation and writes values back
    /// according to the provided bidi configuration.
    public func bindBidi<V: Equatable>(config: RelationBidiConfig<V>, relationToValue: Relation -> V) -> BidiValueBinding<V> {
        return RelationBidiValueBinding(relation: self, config: config, relationToValue: relationToValue, valueChanging: valueChanging)
    }

    /// Returns a bidirectional binding that gets its value from this relation and writes values back
    /// according to the provided bidi configuration.
    public func bindBidi<V>(config: RelationBidiConfig<V?>, relationToValue: Relation -> V?) -> BidiValueBinding<V?> {
        return RelationBidiValueBinding(relation: self, config: config, relationToValue: relationToValue, valueChanging: valueChanging)
    }

    /// Returns a bidirectional binding that gets its value from this relation and writes values back
    /// according to the provided bidi configuration.
    public func bindBidi<V: Equatable>(config: RelationBidiConfig<V?>, relationToValue: Relation -> V?) -> BidiValueBinding<V?> {
        return RelationBidiValueBinding(relation: self, config: config, relationToValue: relationToValue, valueChanging: valueChanging)
    }
}

extension Relation {
    /// A read-only binding that resolves to `true` if there are zero rows in the relation.
    public var empty: ValueBinding<Bool> {
        return bind{ $0.isEmpty.ok == true }
    }
    
    /// A read-only binding that resolves to `true` if there are one or more rows in the relation.
    public var nonEmpty: ValueBinding<Bool> {
        return bind{ $0.isEmpty.ok == false }
    }
    
    /// Returns a read-only binding that resolves to an optional value, which is nil when this
    /// relation is empty and is reconstructed when this relation becomes non-empty.
    public func whenNonEmpty<V>(relationToValue: Relation -> V) -> ValueBinding<V?> {
        return WhenNonEmptyBinding(relation: self, relationToValue: relationToValue)
    }
    
    /// Returns a read-only binding that resolves to the given string value if there are multiple
    /// values in the relation, otherwise resolves to the alternate string.
    public func stringWhenMulti(string: String, otherwise: String = "") -> ValueBinding<String> {
        // TODO: Reimplement in terms of other bindings
        return bind{ $0.allValues.count > 1 ? string : otherwise }
    }
}

extension Relation {
    /// Performs an update using a single RelationValue.
    public func updateValue(value: RelationValue) {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        let row: Row = [attr: value]
        var mutableRelation = self
        mutableRelation.update(true, newValues: row)
    }

    /// Performs an update using a single string value.
    public func updateString(value: String) {
        updateValue(RelationValue(value))
    }

    /// Performs an update using a single optional string value.
    public func updateNullableString(value: String?) {
        let rv: RelationValue
        if let value = value {
            rv = RelationValue(value)
        } else {
            rv = .NULL
        }
        updateValue(rv)
    }

    /// Performs an update using a single integer value.
    public func updateInteger(value: Int64) {
        updateValue(RelationValue(value))
    }
    
    /// Performs an update using a single boolean value (converted to 0 for `false` and 1 for `true`).
    public func updateBoolean(value: Bool) {
        updateValue(RelationValue(Int64(value ? 1 : 0)))
    }
}

extension MutableRelation {
    /// Replaces the given values by performing a delete followed by an add for each value.
    public func replaceValues(values: [RelationValue]) {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        var mutableRelation = self
        mutableRelation.delete(true)
        for id in values {
            mutableRelation.add([attr: id])
        }
    }
}
