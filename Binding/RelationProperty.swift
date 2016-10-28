//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import libRelational

private class RelationProperty<T>: ReadableProperty<T> {
    private var removal: ObserverRemoval!
    
    init(relation: Relation, relationToValue: @escaping (Relation) -> T, valueChanging: @escaping (T, T) -> Bool) {
        let (signal, notify) = Signal<T>.pipe()
        
        super.init(initialValue: relationToValue(relation), signal: signal, notify: notify, changing: valueChanging)
        
        self.removal = relation.addChangeObserver({ [weak self] _ in
            guard let strongSelf = self else { return }
            let newValue = relationToValue(relation)
            strongSelf.setValue(newValue, ChangeMetadata(transient: false))
        })
    }
    
    deinit {
        removal()
    }
}

private class WhenNonEmptyProperty<T>: ReadableProperty<T?> {
    private var removal: ObserverRemoval!
    
    init(relation: Relation, relationToValue: @escaping (Relation) -> T) {
        
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
            guard let strongSelf = self else { return }
            
            // Only re-evaluate if the relation is going from empty to non-empty or vice versa
            if strongSelf.value == nil {
                if let newValue = evaluate() {
                    strongSelf.setValue(newValue, ChangeMetadata(transient: false))
                }
            } else {
                if relation.isEmpty.ok != false {
                    strongSelf.setValue(nil, ChangeMetadata(transient: false))
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
    public func property<V>(_ relationToValue: @escaping (Relation) -> V) -> ReadableProperty<V> {
        return RelationProperty(relation: self, relationToValue: relationToValue, valueChanging: valueChanging)
    }
    
    /// Returns a ReadableProperty that gets its value from this relation.
    public func property<V: Equatable>(_ relationToValue: @escaping (Relation) -> V) -> ReadableProperty<V> {
        return RelationProperty(relation: self, relationToValue: relationToValue, valueChanging: valueChanging)
    }
    
    /// Returns a ReadableProperty that gets its value from this relation.
    public func property<V>(_ relationToValue: @escaping (Relation) -> V?) -> ReadableProperty<V?> {
        return RelationProperty(relation: self, relationToValue: relationToValue, valueChanging: valueChanging)
    }
    
    /// Returns a ReadableProperty that gets its value from this relation.
    public func property<V: Equatable>(_ relationToValue: @escaping (Relation) -> V?) -> ReadableProperty<V?> {
        return RelationProperty(relation: self, relationToValue: relationToValue, valueChanging: valueChanging)
    }
    
    /// Returns a ReadableProperty that resolves to a set of all values for the single attribute.
    public func allValuesProperty<V: Hashable>(_ transform: @escaping (RelationValue) -> V?) -> ReadableProperty<Set<V>> {
        return property{ $0.allValues(transform) }
    }
    
    /// Returns a ReadableProperty that resolves to some value for the single attribute, or nil if there are
    /// no non-error rows.
    public func anyValueProperty<V>(_ transform: @escaping (RelationValue) -> V?) -> ReadableProperty<V?> {
        return property{ $0.anyValue(transform) }
    }
    
    /// Returns a ReadableProperty that resolves to some value for the single attribute, or nil if there are
    /// no non-error rows.
    public func anyValueProperty<V: Equatable>(_ transform: @escaping (RelationValue) -> V?) -> ReadableProperty<V?> {
        return property{ $0.anyValue(transform) }
    }
    
    /// Returns a ReadableProperty that resolves to a single value if there is exactly one row in the relation,
    /// otherwise resolves to nil.
    public func oneValueProperty<V>(_ transform: @escaping (RelationValue) -> V?) -> ReadableProperty<V?> {
        return property{ $0.oneValue(transform) }
    }
    
    /// Returns a ReadableProperty that resolves to a single value if there is exactly one row in the relation,
    /// otherwise resolves to nil.
    public func oneValueProperty<V: Equatable>(_ transform: @escaping (RelationValue) -> V?) -> ReadableProperty<V?> {
        return property{ $0.oneValue(transform) }
    }
}

extension Relation {
    /// Returns a ReadableProperty that resolves to `true` if there are zero rows in the relation.
    public var empty: ReadableProperty<Bool> {
        return property{ $0.isEmpty.ok == true }
    }
    
    /// Returns a ReadableProperty that resolves to `true` if there are one or more rows in the relation.
    public var nonEmpty: ReadableProperty<Bool> {
        return property{ $0.isEmpty.ok == false }
    }
    
    /// Returns a ReadableProperty that resolves to an optional value, which is nil when this
    /// relation is empty and is reconstructed when this relation becomes non-empty.
    public func whenNonEmpty<V>(_ relationToValue: @escaping (Relation) -> V) -> ReadableProperty<V?> {
        return WhenNonEmptyProperty(relation: self, relationToValue: relationToValue)
    }
    
    /// Returns a ReadableProperty that resolves to the given string value if there are multiple
    /// values in the relation, otherwise resolves to the alternate string.
    public func stringWhenMulti(_ string: String, otherwise: String = "") -> ReadableProperty<String> {
        // TODO: Reimplement this using `count` (no need to gather all values first)
        return property{ $0.allValues().count > 1 ? string : otherwise }
    }
}

public struct RelationMutationConfig<T> {
    public let snapshot: () -> ChangeLoggingDatabaseSnapshot
    public let update: (_ newValue: T) -> Void
    public let commit: (_ before: ChangeLoggingDatabaseSnapshot, _ newValue: T) -> Void
    
    public init(
        snapshot: @escaping () -> ChangeLoggingDatabaseSnapshot,
        update: @escaping (_ newValue: T) -> Void,
        commit: @escaping (_ before: ChangeLoggingDatabaseSnapshot, _ newValue: T) -> Void)
    {
        self.snapshot = snapshot
        self.update = update
        self.commit = commit
    }
}

private class RelationReadWriteProperty<T>: ReadWriteProperty<T> {
    private let config: RelationMutationConfig<T>
    private var mutableValue: T
    private var removal: ObserverRemoval!
    private var before: ChangeLoggingDatabaseSnapshot?

    init(relation: Relation, config: RelationMutationConfig<T>, relationToValue: @escaping (Relation) -> T, valueChanging: @escaping (T, T) -> Bool) {
        let (signal, notify) = Signal<T>.pipe()
        
        self.config = config
        self.mutableValue = relationToValue(relation)

        super.init(
            signal: signal,
            notify: notify,
            // TODO
            changeHandler: ChangeHandler()
        )

        self.removal = relation.addChangeObserver({ [weak self] _ in
            guard let strongSelf = self else { return }
            let newValue = relationToValue(relation)
            if valueChanging(strongSelf.mutableValue, newValue) {
                strongSelf.mutableValue = newValue
                notify.valueChanging(newValue, ChangeMetadata(transient: false))
            }
        })
    }

    deinit {
        removal()
    }
    
    fileprivate override func getValue() -> T {
        return mutableValue
    }
    
    fileprivate override func setValue(_ value: T, _ metadata: ChangeMetadata) {
        if before == nil {
            before = config.snapshot()
        }
        
        // Note: We don't set `mutableValue` here; instead we wait to receive the change from the
        // relation in our change observer and then update `mutableValue` there
        if metadata.transient {
            config.update(value)
        } else {
            config.commit(before!, value)
            before = nil
        }
    }
}

extension Relation {
    /// Returns a ReadWriteProperty that gets its value from this relation and writes values back to the relation
    /// according to the provided configuration.
    public func property<V>(_ config: RelationMutationConfig<V>, relationToValue: @escaping (Relation) -> V) -> ReadWriteProperty<V> {
        return RelationReadWriteProperty(relation: self, config: config, relationToValue: relationToValue, valueChanging: valueChanging)
    }

    /// Returns a ReadWriteProperty that gets its value from this relation and writes values back to the relation
    /// according to the provided configuration.
    public func property<V: Equatable>(_ config: RelationMutationConfig<V>, relationToValue: @escaping (Relation) -> V) -> ReadWriteProperty<V> {
        return RelationReadWriteProperty(relation: self, config: config, relationToValue: relationToValue, valueChanging: valueChanging)
    }

    /// Returns a ReadWriteProperty that gets its value from this relation and writes values back to the relation
    /// according to the provided configuration.
    public func property<V>(_ config: RelationMutationConfig<V?>, relationToValue: @escaping (Relation) -> V?) -> ReadWriteProperty<V?> {
        return RelationReadWriteProperty(relation: self, config: config, relationToValue: relationToValue, valueChanging: valueChanging)
    }

    /// Returns a ReadWriteProperty that gets its value from this relation and writes values back to the relation
    /// according to the provided configuration.
    public func property<V: Equatable>(_ config: RelationMutationConfig<V?>, relationToValue: @escaping (Relation) -> V?) -> ReadWriteProperty<V?> {
        return RelationReadWriteProperty(relation: self, config: config, relationToValue: relationToValue, valueChanging: valueChanging)
    }
}
