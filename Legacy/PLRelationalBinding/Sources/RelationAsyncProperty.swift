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
    private let mutator: RelationMutationConfig<T>
    private var before: TransactionalDatabaseSnapshot?

    init(signal: Signal<T>, mutator: RelationMutationConfig<T>) {
        self.mutator = mutator
        
        super.init(signal: signal)
    }
    
    fileprivate override func setValue(_ value: T, _ metadata: ChangeMetadata) {
        if before == nil {
            before = mutator.snapshot()
        }
        
        // Note: We don't set `mutableValue` here; instead we wait to receive the change from the
        // relation in our signal observer and then update `mutableValue` there
        if metadata.transient {
            mutator.update(value)
        } else {
            mutator.commit(before!, value)
            before = nil
        }
    }
}

extension SignalType {
    
    // MARK: Relation / AsyncReadWriteProperty convenience
    
    /// Lifts this signal into an AsyncReadWriteProperty that writes values back to a relation via the given mutator.
    public func property(mutator: RelationMutationConfig<Value>) -> AsyncReadWriteProperty<Value> {
        return RelationAsyncReadWriteProperty(signal: signal, mutator: mutator)
    }
}
