//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import PLRelational
import PLRelationalBinding

public class UndoableDatabase {
    
    private let db: TransactionalDatabase
    private let undoManager: UndoManager
    
    public init(db: TransactionalDatabase, undoManager: UndoManager) {
        self.db = db
        self.undoManager = undoManager
    }
    
    public func performUndoableAction(_ name: String, before: TransactionalDatabaseSnapshot?, _ transactionFunc: @escaping (Void) -> Void) {
        let deltaPromise = Promise<TransactionalDatabaseDelta>()
        
        var before: TransactionalDatabaseSnapshot!
        AsyncManager.currentInstance.registerCheckpoint({
            before = self.db.takeSnapshot()
        })
        transactionFunc()
        AsyncManager.currentInstance.registerCheckpoint({
            let after = self.db.takeSnapshot()
            let delta = self.db.computeDelta(from: before, to: after)
            deltaPromise.fulfill(delta)
        })
        
        undoManager.registerChange(
            name: name,
            perform: false,
            forward: {
                self.db.asyncApply(delta: deltaPromise.get())
            },
            backward: {
                self.db.asyncApply(delta: deltaPromise.get().reversed)
            }
        )
    }

    public func bidiProperty<T>(action: String, signal: Signal<T>, update: @escaping (T) -> Void) -> AsyncReadWriteProperty<T> {
        let config = mutationConfig(action, update)
        return signal.property(mutator: config)
    }
    
    private func mutationConfig<T>(_ action: String, _ update: @escaping (T) -> Void) -> RelationMutationConfig<T> {
        return RelationMutationConfig(
            snapshot: {
                return self.db.takeSnapshot()
            },
            update: { newValue in
                update(newValue)
            },
            commit: { before, newValue in
                self.performUndoableAction(action, before: before, {
                    update(newValue)
                })
            }
        )
    }
}
