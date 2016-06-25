//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import libRelational

private class RelationProperty<T>: ReadableProperty<T> {
    private var removal: ObserverRemoval!
    
    init(relation: Relation, relationToValue: Relation -> T, valueChanging: (T, T) -> Bool) {
        let (signal, notify) = Signal<T>.pipe()
        
        super.init(initialValue: relationToValue(relation), signal: signal, notify: notify, changing: valueChanging)
        
        self.removal = relation.addChangeObserver({ [weak self] _ in
            guard let weakSelf = self else { return }
            let newValue = relationToValue(relation)
            weakSelf.setValue(newValue, ChangeMetadata(transient: false))
        })
    }
    
    deinit {
        removal()
    }
}

private class WhenNonEmptyProperty<T>: ReadableProperty<T?> {
    private var removal: ObserverRemoval!
    
    init(relation: Relation, relationToValue: Relation -> T) {
        
        func evaluate() -> T? {
            if relation.isEmpty.ok == false {
                return relationToValue(relation)
            } else {
                return nil
            }
        }
        
        let (signal, notify) = Signal<T?>.pipe()
        
        super.init(initialValue: evaluate(), signal: signal, notify: notify, changing: valueChanging)
        
        self.removal = relation.addChangeObserver({ [weak self] _ in
            guard let weakSelf = self else { return }
            
            // Only re-evaluate if the relation is going from empty to non-empty or vice versa
            if weakSelf.value == nil {
                if let newValue = evaluate() {
                    weakSelf.setValue(newValue, ChangeMetadata(transient: false))
                }
            } else {
                if relation.isEmpty.ok != false {
                    weakSelf.setValue(nil, ChangeMetadata(transient: false))
                }
            }
        })
    }
    
    deinit {
        removal()
    }
}

extension Relation {
    /// Returns a ReadableProperty that gets its value from this relation.
    public func property<V>(relationToValue: Relation -> V) -> ReadableProperty<V> {
        return RelationProperty(relation: self, relationToValue: relationToValue, valueChanging: valueChanging)
    }
    
    /// Returns a ReadableProperty that gets its value from this relation.
    public func property<V: Equatable>(relationToValue: Relation -> V) -> ReadableProperty<V> {
        return RelationProperty(relation: self, relationToValue: relationToValue, valueChanging: valueChanging)
    }
    
    /// Returns a ReadableProperty that gets its value from this relation.
    public func property<V>(relationToValue: Relation -> V?) -> ReadableProperty<V?> {
        return RelationProperty(relation: self, relationToValue: relationToValue, valueChanging: valueChanging)
    }
    
    /// Returns a ReadableProperty that gets its value from this relation.
    public func property<V: Equatable>(relationToValue: Relation -> V?) -> ReadableProperty<V?> {
        return RelationProperty(relation: self, relationToValue: relationToValue, valueChanging: valueChanging)
    }
    
    /// Returns a ReadableProperty that resolves to a set of all values for the single attribute.
    public func allValuesProperty<V: Hashable>(transform: RelationValue -> V?) -> ReadableProperty<Set<V>> {
        return property{ $0.allValues(transform) }
    }
    
    /// Returns a ReadableProperty that resolves to some value for the single attribute, or nil if there are
    /// no non-error rows.
    public func anyValueProperty<V>(transform: RelationValue -> V?) -> ReadableProperty<V?> {
        return property{ $0.anyValue(transform) }
    }
    
    /// Returns a ReadableProperty that resolves to some value for the single attribute, or nil if there are
    /// no non-error rows.
    public func anyValueProperty<V: Equatable>(transform: RelationValue -> V?) -> ReadableProperty<V?> {
        return property{ $0.anyValue(transform) }
    }
    
    /// Returns a ReadableProperty that resolves to a single value if there is exactly one row in the relation,
    /// otherwise resolves to nil.
    public func oneValueProperty<V>(transform: RelationValue -> V?) -> ReadableProperty<V?> {
        return property{ $0.oneValue(transform) }
    }
    
    /// Returns a ReadableProperty that resolves to a single value if there is exactly one row in the relation,
    /// otherwise resolves to nil.
    public func oneValueProperty<V: Equatable>(transform: RelationValue -> V?) -> ReadableProperty<V?> {
        return property{ $0.oneValue(transform) }
    }
}

extension Relation {
    /// a ReadableProperty that resolves to `true` if there are zero rows in the relation.
    public var empty: ReadableProperty<Bool> {
        return property{ $0.isEmpty.ok == true }
    }
    
    /// a ReadableProperty that resolves to `true` if there are one or more rows in the relation.
    public var nonEmpty: ReadableProperty<Bool> {
        return property{ $0.isEmpty.ok == false }
    }
    
    /// Returns a ReadableProperty that resolves to an optional value, which is nil when this
    /// relation is empty and is reconstructed when this relation becomes non-empty.
    public func whenNonEmpty<V>(relationToValue: Relation -> V) -> ReadableProperty<V?> {
        return WhenNonEmptyProperty(relation: self, relationToValue: relationToValue)
    }
    
    /// Returns a ReadableProperty that resolves to the given string value if there are multiple
    /// values in the relation, otherwise resolves to the alternate string.
    public func stringWhenMulti(string: String, otherwise: String = "") -> ReadableProperty<String> {
        // TODO: Reimplement this using `count` (no need to gather all values first)
        return property{ $0.allValues.count > 1 ? string : otherwise }
    }
}
