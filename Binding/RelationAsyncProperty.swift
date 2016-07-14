//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import libRelational

extension Relation {
    /// Returns an AsyncReadableProperty that gets its value from this relation.
    public func asyncProperty<S: SignalType>(relationToSignal: Relation -> S) -> AsyncReadableProperty<S.Value> {
        return AsyncReadableProperty(relationToSignal(self).signal)
    }
}

private class RelationAsyncReadWriteProperty<T>: AsyncReadWriteProperty<T> {
    private var removal: ObserverRemoval!
    
    init(config: RelationMutationConfig<T>, signal: Signal<T>) {
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
            signal: signal
        )
        
        self.removal = signal.observe({ newValue, _ in
            value = newValue
        })
    }
    
    deinit {
        removal()
    }
}

extension Relation {
    /// Returns an AsyncReadWriteProperty that gets its value from this relation and writes values back to the relation
    /// according to the provided configuration.
    public func asyncProperty<S: SignalType>(config: RelationMutationConfig<S.Value>, signal: S) -> AsyncReadWriteProperty<S.Value> {
        return RelationAsyncReadWriteProperty(config: config, signal: signal.signal)
    }
}
