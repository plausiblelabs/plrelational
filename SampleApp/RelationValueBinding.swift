//
//  RelationBinding.swift
//  Relational
//
//  Created by Chris Campbell on 5/21/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import libRelational

private class RelationValueBinding<T>: ValueBinding<T> {
    private var removal: (Void -> Void)!
    
    init(relation: Relation, transform: Relation -> T) {
        super.init(initialValue: transform(relation))
        
        self.removal = relation.addChangeObserver({ [weak self] _ in
            self?.setValue(transform(relation))
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
    private var removal: (Void -> Void)!
    
    init(relation: Relation, config: RelationBidiConfig<T>, transform: Relation -> T) {
        self.config = config

        super.init(initialValue: transform(relation))
    
        self.removal = relation.addChangeObserver({ [weak self] _ in
            guard let weakSelf = self else { return }
            
            if weakSelf.selfInitiatedChange { return }
            
            weakSelf.setValue(transform(relation))
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
        return RelationValueBinding(relation: self, transform: { $0.isEmpty.ok == true })
    }
    
    /// Resolves to `true` if there are one or more rows in the relation.
    var nonEmpty: ValueBinding<Bool> {
        return RelationValueBinding(relation: self, transform: { $0.isEmpty.ok == false })
    }
    
    /// Resolves to a single string value if there is exactly one row in the relation, otherwise resolves
    /// to an empty string.
    var oneString: ValueBinding<String> {
        return RelationValueBinding(relation: self, transform: { relation -> String in
            let values = self.allValues(relation, { value -> String? in value.get() })
            if values.count == 1 {
                return values.first!
            } else {
                return ""
            }
        })
    }
    
    /// Resolves to the given string value if there are multiple string values in the relation, otherwise
    /// resolves to an empty string.
    func stringWhenMulti(string: String) -> ValueBinding<String> {
        return RelationValueBinding(relation: self, transform: { relation -> String in
            let values = self.allValues(relation, { value -> String? in value.get() })
            if values.count > 1 {
                return string
            } else {
                return ""
            }
        })
    }

    /// Resolves to a sequence of all values for the single attribute, one value for each non-error row.
    func all<V>(unwrap: RelationValue -> V?) -> ValueBinding<[V]> {
        return RelationValueBinding(relation: self, transform: { self.allValues($0, unwrap) })
    }

    /// Resolves to some value for the single attribute if there are one or more rows, or nil if there are no non-error rows.
    func any<V>(unwrap: RelationValue -> V?) -> ValueBinding<V?> {
        return RelationValueBinding(relation: self, transform: { self.anyValue($0, unwrap) })
    }

    /// Bidirectional version of `oneString` binding.
    func bidiString(config: RelationBidiConfig<String>) -> BidiValueBinding<String> {
        return RelationBidiValueBinding(relation: self, config: config, transform: { relation -> String in
            let values = self.allValues(relation, { value -> String? in value.get() })
            if values.count == 1 {
                return values.first!
            } else {
                return ""
            }
        })
    }
    
    /// Bidirectional version of `all` binding with RelationValue elements.
    func bidiValues(config: RelationBidiConfig<[RelationValue]>) -> BidiValueBinding<[RelationValue]> {
        return RelationBidiValueBinding(relation: self, config: config, transform: { relation -> [RelationValue] in
            return self.allValues(relation, { $0 })
        })
    }
    
    /// Resolves to a sequence of all values for the single attribute, one value for each non-error row.
    private func allValues<V>(relation: Relation, _ unwrap: RelationValue -> V?) -> [V] {
        precondition(relation.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = relation.scheme.attributes.first!
        return relation.rows().flatMap{$0.ok}.flatMap{unwrap($0[attr])}
    }
    
    /// Resolves to some value for the single attribute if there are one or more rows, or nil if there are no non-error rows.
    private func anyValue<V>(relation: Relation, _ unwrap: RelationValue -> V?) -> V? {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        if let row = self.rows().next()?.ok {
            return unwrap(row[attr])
        } else {
            return nil
        }
    }
}
