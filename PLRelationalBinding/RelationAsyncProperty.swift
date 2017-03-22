//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import PLRelational

public struct RelationMutationConfig<T> {
    public let snapshot: () -> TransactionalDatabaseSnapshot
    public let update: (_ newValue: T) -> Void
    public let commit: (_ before: TransactionalDatabaseSnapshot, _ newValue: T) -> Void

    public init(
        snapshot: @escaping () -> TransactionalDatabaseSnapshot,
        update: @escaping (_ newValue: T) -> Void,
        commit: @escaping (_ before: TransactionalDatabaseSnapshot, _ newValue: T) -> Void)
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
    private var before: TransactionalDatabaseSnapshot?

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

extension SignalType {
    /// Lifts this signal into an AsyncReadWriteProperty that writes values back to a relation via the given mutator.
    public func property(mutator: RelationMutationConfig<Value>) -> AsyncReadWriteProperty<Value> {
        // XXX: This is awful; might be slightly less awful if we had a more formal notion of a Signal that
        // provides access to its latest value
        let signal = self.signal
        let initialValue: Value?
        if let relationSignal = signal as? RelationSignal<Self.Value> {
            initialValue = relationSignal.latestValue
        } else {
            initialValue = nil
        }
        return RelationAsyncReadWriteProperty(initialValue: initialValue, config: mutator, signal: signal)
    }
}
