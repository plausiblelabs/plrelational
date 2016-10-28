//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import libRelational

extension Relation {
    /// Returns an AsyncReadableProperty that gets its value from this relation.
    public func asyncProperty<S: SignalType>(_ relationToSignal: (Relation) -> S) -> AsyncReadableProperty<S.Value> {
        return AsyncReadableProperty(initialValue: nil, signal: relationToSignal(self).signal)
    }

    /// Returns an AsyncReadableProperty that gets its value from this relation.
    public func asyncProperty<S: SignalType>(initialValue: S.Value, _ relationToSignal: (Relation) -> S) -> AsyncReadableProperty<S.Value> {
        return AsyncReadableProperty(initialValue: initialValue, signal: relationToSignal(self).signal)
    }

    /// Returns an AsyncReadableProperty that gets its value from this relation using the given transform.
    public func asyncProperty<T>(_ rowsToValue: @escaping (Relation, AnyIterator<Row>) -> T) -> AsyncReadableProperty<T> {
        return AsyncReadableProperty(initialValue: nil, signal: self.signal(rowsToValue))
    }

    /// Returns an AsyncReadableProperty that gets its value from this relation using the given transform.
    public func asyncProperty<T>(initialValue: T?, _ rowsToValue: @escaping (Relation, AnyIterator<Row>) -> T) -> AsyncReadableProperty<T> {
        return AsyncReadableProperty(initialValue: initialValue, signal: self.signal(rowsToValue))
    }

    /// Returns an AsyncReadableProperty that gets its value from this relation using the given transform.
    public func asyncProperty<T: Equatable>(_ rowsToValue: @escaping (Relation, AnyIterator<Row>) -> T) -> AsyncReadableProperty<T> {
        return AsyncReadableProperty(initialValue: nil, signal: self.signal(rowsToValue))
    }

    /// Returns an AsyncReadableProperty that gets its value from this relation using the given transform.
    public func asyncProperty<T: Equatable>(initialValue: T?, _ rowsToValue: @escaping (Relation, AnyIterator<Row>) -> T) -> AsyncReadableProperty<T> {
        return AsyncReadableProperty(initialValue: initialValue, signal: self.signal(rowsToValue))
    }

    /// Returns an AsyncReadableProperty that gets its value from this relation using the given transform.
    public func asyncProperty<T>(_ rowsToValue: @escaping (Relation, AnyIterator<Row>) -> T?) -> AsyncReadableProperty<T?> {
        return AsyncReadableProperty(initialValue: nil, signal: self.signal(rowsToValue))
    }
    
    /// Returns an AsyncReadableProperty that gets its value from this relation using the given transform.
    public func asyncProperty<T: Equatable>(_ rowsToValue: @escaping (Relation, AnyIterator<Row>) -> T?) -> AsyncReadableProperty<T?> {
        return AsyncReadableProperty(initialValue: nil, signal: self.signal(rowsToValue))
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
    public func asyncProperty<S: SignalType>(config: RelationMutationConfig<S.Value>, _ relationToSignal: (Relation) -> S) -> AsyncReadWriteProperty<S.Value> {
        return RelationAsyncReadWriteProperty(initialValue: nil, config: config, signal: relationToSignal(self).signal)
    }
    
    /// Returns an AsyncReadWriteProperty that gets its value from this relation and writes values back to the relation
    /// according to the provided configuration.
    public func asyncProperty<S: SignalType>(initialValue: S.Value?, config: RelationMutationConfig<S.Value>, _ relationToSignal: (Relation) -> S) -> AsyncReadWriteProperty<S.Value> {
        return RelationAsyncReadWriteProperty(initialValue: initialValue, config: config, signal: relationToSignal(self).signal)
    }
}
