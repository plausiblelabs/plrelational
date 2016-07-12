//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import libRelational

private class RelationAsyncProperty<T>: AsyncReadableProperty<T> {
    private var removal: ObserverRemoval!
    
    init(relation: Relation, relationToValue: Relation -> T) {
        let (signal, notify) = Signal<T>.pipe()
        
        super.init(signal: signal, notify: notify)
        
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

extension Relation {
    /// Returns an AsyncReadableProperty that gets its value from this relation.
    public func asyncProperty<V>(relationToValue: Relation -> V) -> AsyncReadableProperty<V> {
        return RelationAsyncProperty(relation: self, relationToValue: relationToValue)
    }
}

private class RelationAsyncReadWriteProperty<T>: AsyncReadWriteProperty<T> {
    private var removal: ObserverRemoval!
    
    init(relation: Relation, config: RelationMutationConfig<T>, relationToValue: Relation -> T) {
        let (signal, notify) = Signal<T>.pipe()
        
        var value: T?
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
            notify: notify,
            // TODO
            changeHandler: ChangeHandler()
        )
        
        self.removal = relation.addChangeObserver({ _ in
            let newValue = relationToValue(relation)
            value = newValue
            notify.valueChanging(change: newValue, metadata: ChangeMetadata(transient: false))
        })
    }
    
    deinit {
        removal()
    }
}

extension Relation {
    /// Returns an AsyncReadWriteProperty that gets its value from this relation and writes values back to the relation
    /// according to the provided configuration.
    public func asyncProperty<V>(config: RelationMutationConfig<V>, relationToValue: Relation -> V) -> AsyncReadWriteProperty<V> {
        return RelationAsyncReadWriteProperty(relation: self, config: config, relationToValue: relationToValue)
    }
}
