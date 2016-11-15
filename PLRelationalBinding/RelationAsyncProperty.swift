//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import PLRelational

extension Relation {
    /// Returns an AsyncReadableProperty that gets its value from this relation.
    public func property<S: SignalType>(_ relationToSignal: (Relation) -> S) -> AsyncReadableProperty<S.Value> {
        return AsyncReadableProperty(initialValue: nil, signal: relationToSignal(self).signal)
    }

    /// Returns an AsyncReadableProperty that gets its value from this relation.
    public func property<S: SignalType>(initialValue: S.Value, _ relationToSignal: (Relation) -> S) -> AsyncReadableProperty<S.Value> {
        return AsyncReadableProperty(initialValue: initialValue, signal: relationToSignal(self).signal)
    }

    /// Returns an AsyncReadableProperty that gets its value from this relation using the given transform.
    public func property<T>(_ rowsToValue: @escaping (Relation, AnyIterator<Row>) -> T) -> AsyncReadableProperty<T> {
        return AsyncReadableProperty(initialValue: nil, signal: self.signal(rowsToValue))
    }

    /// Returns an AsyncReadableProperty that gets its value from this relation using the given transform.
    public func property<T>(initialValue: T?, _ rowsToValue: @escaping (Relation, AnyIterator<Row>) -> T) -> AsyncReadableProperty<T> {
        return AsyncReadableProperty(initialValue: initialValue, signal: self.signal(rowsToValue))
    }

    /// Returns an AsyncReadableProperty that gets its value from this relation using the given transform.
    public func property<T: Equatable>(_ rowsToValue: @escaping (Relation, AnyIterator<Row>) -> T) -> AsyncReadableProperty<T> {
        return AsyncReadableProperty(initialValue: nil, signal: self.signal(rowsToValue))
    }

    /// Returns an AsyncReadableProperty that gets its value from this relation using the given transform.
    public func property<T: Equatable>(initialValue: T?, _ rowsToValue: @escaping (Relation, AnyIterator<Row>) -> T) -> AsyncReadableProperty<T> {
        return AsyncReadableProperty(initialValue: initialValue, signal: self.signal(rowsToValue))
    }

    /// Returns an AsyncReadableProperty that gets its value from this relation using the given transform.
    public func property<T>(_ rowsToValue: @escaping (Relation, AnyIterator<Row>) -> T?) -> AsyncReadableProperty<T?> {
        return AsyncReadableProperty(initialValue: nil, signal: self.signal(rowsToValue))
    }
    
    /// Returns an AsyncReadableProperty that gets its value from this relation using the given transform.
    public func property<T: Equatable>(_ rowsToValue: @escaping (Relation, AnyIterator<Row>) -> T?) -> AsyncReadableProperty<T?> {
        return AsyncReadableProperty(initialValue: nil, signal: self.signal(rowsToValue))
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

private class RelationAsyncReadWriteProperty<T>: AsyncReadWriteProperty<T> {
    private let config: RelationMutationConfig<T>
    private var mutableValue: T?
    private var removal: ObserverRemoval?
    private var before: ChangeLoggingDatabaseSnapshot?

    init(initialValue: T?, config: RelationMutationConfig<T>, signal: Signal<T>) {
        self.mutableValue = initialValue
        self.config = config
        
        super.init(signal: signal)
    }
    
    deinit {
        removal?()
    }
    
    fileprivate override func startImpl() {
        let deliverInitial = mutableValue == nil
        removal = signal.observe({ [weak self] newValue, _ in
            self?.mutableValue = newValue
        })
        signal.start(deliverInitial: deliverInitial)
    }
    
    fileprivate override func getValue() -> T? {
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
    /// Returns an AsyncReadWriteProperty that gets its value from this relation and writes values back to the relation
    /// according to the provided configuration.
    public func property<S: SignalType>(config: RelationMutationConfig<S.Value>, _ relationToSignal: (Relation) -> S) -> AsyncReadWriteProperty<S.Value> {
        return RelationAsyncReadWriteProperty(initialValue: nil, config: config, signal: relationToSignal(self).signal)
    }
    
    /// Returns an AsyncReadWriteProperty that gets its value from this relation and writes values back to the relation
    /// according to the provided configuration.
    public func property<S: SignalType>(initialValue: S.Value?, config: RelationMutationConfig<S.Value>, _ relationToSignal: (Relation) -> S) -> AsyncReadWriteProperty<S.Value> {
        return RelationAsyncReadWriteProperty(initialValue: initialValue, config: config, signal: relationToSignal(self).signal)
    }
}

extension RelationMutationConfig {
    /// Returns an AsyncReadWriteProperty that gets its value from a relation and writes values back to a relation
    /// according to this configuration.
    public func property<S: SignalType>(signal: S) -> AsyncReadWriteProperty<S.Value> where T == S.Value {
        return RelationAsyncReadWriteProperty(initialValue: nil, config: self, signal: signal.signal)
    }

    /// Returns an AsyncReadWriteProperty that gets its value from a relation and writes values back to a relation
    /// according to this configuration.
    public func property<S: SignalType>(initialValue: S.Value?, signal: S) -> AsyncReadWriteProperty<S.Value> where T == S.Value {
        return RelationAsyncReadWriteProperty(initialValue: initialValue, config: self, signal: signal.signal)
    }
}
