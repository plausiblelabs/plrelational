//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import libRelational

public struct RelationMutationConfig<T> {
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

private class RelationBidiProperty<T>: BidiProperty<T> {
    private var removal: ObserverRemoval!
    
    init(relation: Relation, config: RelationMutationConfig<T>, relationToValue: Relation -> T, valueChanging: (T, T) -> Bool) {
        let signal: Signal<T>
        let notify: Signal<T>.Notify
        (signal, notify) = Signal.pipe()

        var value = relationToValue(relation)
        var before: ChangeLoggingDatabaseSnapshot?

        super.init(
            get: { value },
            set: { newValue, metadata in
                if before == nil {
                    before = config.snapshot()
                }
                
                // Note: We don't set `value` here; instead we wait to receive the change from the
                // relation in our change observer and then update `value` there
                if metadata.transient {
                    config.update(newValue: newValue)
                } else {
                    config.commit(before: before!, newValue: newValue)
                    before = nil
                }
            },
            signal: signal,
            notify: notify
        )
        
        self.removal = relation.addChangeObserver({ _ in
            let newValue = relationToValue(relation)
            if valueChanging(value, newValue) {
                value = newValue
                notify(newValue: newValue, metadata: ChangeMetadata(transient: false))
            }
        })
    }

    deinit {
        removal()
    }
}

extension Relation {
    /// Returns a BidiProperty that gets its value from this relation and writes values back to the relation
    /// according to the provided configuration.
    public func bidiProperty<V>(config: RelationMutationConfig<V>, relationToValue: Relation -> V) -> BidiProperty<V> {
        return RelationBidiProperty(relation: self, config: config, relationToValue: relationToValue, valueChanging: valueChanging)
    }
    
    /// Returns a BidiProperty that gets its value from this relation and writes values back to the relation
    /// according to the provided configuration.
    public func bidiProperty<V: Equatable>(config: RelationMutationConfig<V>, relationToValue: Relation -> V) -> BidiProperty<V> {
        return RelationBidiProperty(relation: self, config: config, relationToValue: relationToValue, valueChanging: valueChanging)
    }

    /// Returns a BidiProperty that gets its value from this relation and writes values back to the relation
    /// according to the provided configuration.
    public func bidiProperty<V>(config: RelationMutationConfig<V?>, relationToValue: Relation -> V?) -> BidiProperty<V?> {
        return RelationBidiProperty(relation: self, config: config, relationToValue: relationToValue, valueChanging: valueChanging)
    }
    
    /// Returns a BidiProperty that gets its value from this relation and writes values back to the relation
    /// according to the provided configuration.
    public func bidiProperty<V: Equatable>(config: RelationMutationConfig<V?>, relationToValue: Relation -> V?) -> BidiProperty<V?> {
        return RelationBidiProperty(relation: self, config: config, relationToValue: relationToValue, valueChanging: valueChanging)
    }
}
