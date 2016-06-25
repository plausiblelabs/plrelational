//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import libRelational

private class RelationObservableValue<T>: ObservableValue<T> {
    private var removal: ObserverRemoval!
    
    init(relation: Relation, relationToValue: Relation -> T, valueChanging: (T, T) -> Bool) {
        super.init(initialValue: relationToValue(relation), valueChanging: valueChanging)
        
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

//private class WhenNonEmpty<T>: ObservableValue<T?> {
//    private var removal: ObserverRemoval!
//    
//    init(relation: Relation, relationToValue: Relation -> T) {
//
//        func evaluate() -> T? {
//            if relation.isEmpty.ok == false {
//                return relationToValue(relation)
//            } else {
//                return nil
//            }
//        }
//        
//        super.init(initialValue: evaluate())
//        
//        self.removal = relation.addChangeObserver({ [weak self] _ in
//            guard let weakSelf = self else { return }
//            
//            // Only re-evaluate if the relation is going from empty to non-empty or vice versa
//            if weakSelf.value == nil {
//                if let newValue = evaluate() {
//                    weakSelf.setValue(newValue, ChangeMetadata(transient: false))
//                }
//            } else {
//                if relation.isEmpty.ok != false {
//                    weakSelf.setValue(nil, ChangeMetadata(transient: false))
//                }
//            }
//        })
//    }
//    
//    deinit {
//        removal()
//    }
//}
//
//extension Relation {
//    /// Returns a read-only ObservableValue that gets its value from this relation.
//    public func observable<V>(relationToValue: Relation -> V) -> ObservableValue<V> {
//        return RelationObservableValue(relation: self, relationToValue: relationToValue, valueChanging: valueChanging)
//    }
//
//    /// Returns a read-only ObservableValue that gets its value from this relation.
//    public func observable<V: Equatable>(relationToValue: Relation -> V) -> ObservableValue<V> {
//        return RelationObservableValue(relation: self, relationToValue: relationToValue, valueChanging: valueChanging)
//    }
//
//    /// Returns a read-only ObservableValue that gets its value from this relation.
//    public func observable<V>(relationToValue: Relation -> V?) -> ObservableValue<V?> {
//        return RelationObservableValue(relation: self, relationToValue: relationToValue, valueChanging: valueChanging)
//    }
//
//    /// Returns a read-only ObservableValue that gets its value from this relation.
//    public func observable<V: Equatable>(relationToValue: Relation -> V?) -> ObservableValue<V?> {
//        return RelationObservableValue(relation: self, relationToValue: relationToValue, valueChanging: valueChanging)
//    }
//
//    /// Returns a read-only ObservableValue that resolves to a set of all values for the single attribute.
//    public func observableAllValues<V: Hashable>(transform: RelationValue -> V?) -> ObservableValue<Set<V>> {
//        return observable{ $0.allValues(transform) }
//    }
//
//    /// Returns a read-only ObservableValue that resolves to some value for the single attribute, or nil if there are
//    /// no non-error rows.
//    public func observableAnyValue<V>(transform: RelationValue -> V?) -> ObservableValue<V?> {
//        return observable{ $0.anyValue(transform) }
//    }
//
//    /// Returns a read-only ObservableValue that resolves to some value for the single attribute, or nil if there are
//    /// no non-error rows.
//    public func observableAnyValue<V: Equatable>(transform: RelationValue -> V?) -> ObservableValue<V?> {
//        return observable{ $0.anyValue(transform) }
//    }
//
//    /// Returns a read-only ObservableValue that resolves to a single value if there is exactly one row in the relation,
//    /// otherwise resolves to nil.
//    public func observableOneValue<V>(transform: RelationValue -> V?) -> ObservableValue<V?> {
//        return observable{ $0.oneValue(transform) }
//    }
//
//    /// Returns a read-only ObservableValue that resolves to a single value if there is exactly one row in the relation,
//    /// otherwise resolves to nil.
//    public func observableOneValue<V: Equatable>(transform: RelationValue -> V?) -> ObservableValue<V?> {
//        return observable{ $0.oneValue(transform) }
//    }
//}
//
//extension Relation {
//    /// A read-only ObservableValue that resolves to `true` if there are zero rows in the relation.
//    public var empty: ObservableValue<Bool> {
//        return observable{ $0.isEmpty.ok == true }
//    }
//    
//    /// A read-only ObservableValue that resolves to `true` if there are one or more rows in the relation.
//    public var nonEmpty: ObservableValue<Bool> {
//        return observable{ $0.isEmpty.ok == false }
//    }
//    
//    /// Returns a read-only ObservableValue that resolves to an optional value, which is nil when this
//    /// relation is empty and is reconstructed when this relation becomes non-empty.
//    public func whenNonEmpty<V>(relationToValue: Relation -> V) -> ObservableValue<V?> {
//        return WhenNonEmpty(relation: self, relationToValue: relationToValue)
//    }
//    
//    /// Returns a read-only ObservableValue that resolves to the given string value if there are multiple
//    /// values in the relation, otherwise resolves to the alternate string.
//    public func stringWhenMulti(string: String, otherwise: String = "") -> ObservableValue<String> {
//        // TODO: Reimplement this using `count` (no need to gather all values first)
//        return observable{ $0.allValues.count > 1 ? string : otherwise }
//    }
//}
