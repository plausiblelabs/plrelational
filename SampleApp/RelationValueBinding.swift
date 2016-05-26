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
    
    init(relation: Relation, relationToValue: Relation -> T) {
        super.init(initialValue: relationToValue(relation))
        
        self.removal = relation.addChangeObserver({ [weak self] _ in
            self?.setValue(relationToValue(relation))
        })
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

private class RelationBidiValueBinding<T>: BidiValueBinding<T> {
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
            
            weakSelf.setValue(relationToValue(relation))
        })
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

extension Relation {
    /// Resolves to `true` if there are zero rows in the relation.
    var empty: ValueBinding<Bool> {
        return RelationValueBinding(relation: self, relationToValue: { $0.isEmpty.ok == true })
    }
    
    /// Resolves to `true` if there are one or more rows in the relation.
    var nonEmpty: ValueBinding<Bool> {
        return RelationValueBinding(relation: self, relationToValue: { $0.isEmpty.ok == false })
    }
    
    /// Resolves to a single string value if there is exactly one row in the relation, otherwise resolves
    /// to an empty string.
    var oneStringBinding: ValueBinding<String> {
        return RelationValueBinding(relation: self, relationToValue: { relation -> String in
            let values = self.allValues(relation, { value -> String? in value.get() })
            if values.count == 1 {
                return values.first!
            } else {
                return ""
            }
        })
    }

    /// Resolves to a single integer value if there is exactly one row in the relation, otherwise resolves
    /// to zero.
    var oneInteger: ValueBinding<Int64> {
        return RelationValueBinding(relation: self, relationToValue: { relation -> Int64 in
            let values = self.allValues(relation, { value -> Int64? in value.get() })
            if values.count == 1 {
                return values.first!
            } else {
                return 0
            }
        })
    }
    
    /// Resolves to the given string value if there are multiple string values in the relation, otherwise
    /// resolves to an empty string.
    func stringWhenMulti(string: String) -> ValueBinding<String> {
        return RelationValueBinding(relation: self, relationToValue: { relation -> String in
            let values = self.allValues(relation, { value -> String? in value.get() })
            if values.count > 1 {
                return string
            } else {
                return ""
            }
        })
    }
    
    /// Resolves to an optional value, which is nil when this relation is empty and is reconstructed when this
    /// relation becomes non-empty.
    func whenNonEmpty<V>(relationToValue: Relation -> V) -> ValueBinding<V?> {
        return WhenNonEmptyBinding(relation: self, relationToValue: relationToValue)
    }
    
    /// Resolves to a sequence of mapped values, one value for each non-error row.
    func map<V>(rowToValue: Row -> V) -> ValueBinding<[V]> {
        return RelationValueBinding(relation: self, relationToValue: { self.mapRows($0, rowToValue) })
    }

    /// Resolves to a sequence of all values for the single attribute, one value for each non-error row.
    func all<V>(unwrap: RelationValue -> V?) -> ValueBinding<[V]> {
        return RelationValueBinding(relation: self, relationToValue: { self.allValues($0, unwrap) })
    }

    /// Resolves to some value for the single attribute if there are one or more rows, or nil if there are no non-error rows.
    func any<V>(unwrap: RelationValue -> V?) -> ValueBinding<V?> {
        return RelationValueBinding(relation: self, relationToValue: { self.anyValue($0, unwrap) })
    }

    /// Returns a bidirectional binding that wraps this relation.
    func bidiBinding<V>(config: RelationBidiConfig<V>, relationToValue: Relation -> V) -> BidiValueBinding<V> {
        return RelationBidiValueBinding(relation: self, config: config, relationToValue: relationToValue)
    }
    
    /// Resolves to a sequence of all RelationValues for the single attribute, one value for each non-error row.
    var allValues: [RelationValue] {
        return allValues(self, { $0 })
    }
    
    /// Resolves to a single string value if there is exactly one row in the relation, otherwise resolves
    /// to an empty string.
    var oneString: String {
        return oneValue(self, { $0.get() }) ?? ""
    }
    
    /// Resolves to a single boolean value if there is exactly one row in the relation, otherwise resolves
    /// to nil.
    var oneBoolOrNil: Bool? {
        return oneValue(self, { value -> Bool? in
            let intValue: Int64? = value.get()
            if let v = intValue {
                return v != 0
            } else {
                return nil
            }
        })
    }

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

    /// Performs an update using a single integer value.
    func updateInteger(value: Int64) {
        updateValue(RelationValue(value))
    }

    /// Resolves the relation to a sequence of mapped values, one value for each non-error row.
    private func mapRows<V>(relation: Relation, _ rowToValue: Row -> V) -> [V] {
        return relation.rows().flatMap{$0.ok}.map(rowToValue)
    }
    
    /// Resolves the relation to a sequence of all values for the single attribute, one value for
    /// each non-error row.
    private func allValues<V>(relation: Relation, _ unwrap: RelationValue -> V?) -> [V] {
        precondition(relation.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = relation.scheme.attributes.first!
        return relation.rows().flatMap{$0.ok}.flatMap{unwrap($0[attr])}
    }
    
    /// Resolves the relation to some value for the single attribute if there are one or more rows,
    /// or nil if there are no non-error rows.
    private func anyValue<V>(relation: Relation, _ unwrap: RelationValue -> V?) -> V? {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        if let row = self.rows().next()?.ok {
            return unwrap(row[attr])
        } else {
            return nil
        }
    }
    
    /// Resolves the relation to a single value for the single attribute if there is exactly one row,
    /// otherwise resolves to nil.
    private func oneValue<V>(relation: Relation, _ unwrap: RelationValue -> V?) -> V? {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        let rows = self.rows()
        if let row = rows.next()?.ok {
            if rows.next() == nil {
                return unwrap(row[attr])
            } else {
                return nil
            }
        } else {
            return nil
        }
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
