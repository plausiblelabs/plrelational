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
    
    public func performUndoableAction(_ name: String, before: ChangeLoggingDatabaseSnapshot?, _ transactionFunc: @escaping (Void) -> Void) {
        let before = before ?? db.takeSnapshot()
        transactionFunc()
        
        undoManager.registerChange(
            name: name,
            perform: false,
            forward: {
                // TODO: Currently we keep the original `transactionFunc` closure around and apply that
                // as the "forward" operation.  This approach ensures that the specific piece of
                // application logic is (re)applied in case of redo, but it comes with the downside
                // that we may be hanging onto a significant amount of application logic and resources.
                // An alternative approach would be to await completion of the original application of
                // `transactionFunc`, create a snapshot, and then use that snapshot for future "forward"
                // operations when registering the change with UndoManager.  This approach works as long
                // as we assume that no other operations will be queued up while AsyncManager is busy,
                // which is currently a valid assumption.
                transactionFunc()
            },
            backward: {
                self.db.asyncRestoreSnapshot(before)
            }
        )
    }

    public func bidiProperty<T>(action: String, initialValue: T?, signal: Signal<T>, update: @escaping (T) -> Void) -> AsyncReadWriteProperty<T> {
        let config = mutationConfig(action, update)
        return signal.property(mutator: config, initialValue: initialValue)
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
