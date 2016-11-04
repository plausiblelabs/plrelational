//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import PLRelational
import Binding

public class UndoableDatabase {
    
    private let db: TransactionalDatabase
    private let undoManager: UndoManager
    
    public init(db: TransactionalDatabase, undoManager: UndoManager) {
        self.db = db
        self.undoManager = undoManager
    }
    
    public func performUndoableAction(_ name: String, before: ChangeLoggingDatabaseSnapshot?, _ transactionFunc: (Void) -> Void) {
        let before = before ?? db.takeSnapshot()
        db.transaction(transactionFunc)
        let after = db.takeSnapshot()
        
        undoManager.registerChange(
            name: name,
            perform: false,
            forward: {
                self.db.restoreSnapshot(after)
            },
            backward: {
                self.db.restoreSnapshot(before)
            }
        )
    }
    
    /// Note: `set` will be called in the context of a database transaction.
    public func bidiProperty<T: Equatable>(_ relation: Relation, action: String, get: @escaping (Relation) -> T, set: @escaping (T) -> Void) -> ReadWriteProperty<T> {
        return relation.property(mutationConfig(action, set), relationToValue: get)
    }

    /// Note: `set` will be called in the context of a database transaction.
    public func bidiProperty<T: Equatable>(_ relation: Relation, action: String, get: @escaping (Relation) -> T?, set: @escaping (T?) -> Void) -> ReadWriteProperty<T?> {
        return relation.property(mutationConfig(action, set), relationToValue: get)
    }

    private func mutationConfig<T>(_ action: String, _ set: @escaping (T) -> Void) -> RelationMutationConfig<T> {
        return RelationMutationConfig(
            snapshot: {
                return self.db.takeSnapshot()
            },
            update: { newValue in
                // TODO: We wrap this in a transaction to keep it atomic, but we don't actually
                // need to log the changes anywhere
                self.db.transaction{
                    set(newValue)
                }
            },
            commit: { before, newValue in
                self.performUndoableAction(action, before: before, {
                    set(newValue)
                })
            }
        )
    }
    
    public func performUndoableAsyncAction(_ name: String, before: ChangeLoggingDatabaseSnapshot?, _ transactionFunc: @escaping (Void) -> Void) {
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
                // as we assume that no other operations will be queued up while UpdateManager is busy,
                // which is currently a valid assumption.
                transactionFunc()
            },
            backward: {
                self.db.asyncRestoreSnapshot(before)
            }
        )
    }

    public func asyncBidiProperty<T>(action: String, initialValue: T?, signal: Signal<T>, update: @escaping (T) -> Void) -> AsyncReadWriteProperty<T> {
        let config = asyncMutationConfig(action, update)
        return config.asyncProperty(initialValue: initialValue, signal: signal)
    }

    public func asyncBidiProperty<T>(action: String, signal: Signal<T>, update: @escaping (T) -> Void) -> AsyncReadWriteProperty<T> {
        let config = asyncMutationConfig(action, update)
        return config.asyncProperty(signal: signal)
    }
    
    private func asyncMutationConfig<T>(_ action: String, _ update: @escaping (T) -> Void) -> RelationMutationConfig<T> {
        return RelationMutationConfig(
            snapshot: {
                return self.db.takeSnapshot()
            },
            update: { newValue in
                // TODO: Need explicit transaction here
                update(newValue)
            },
            commit: { before, newValue in
                self.performUndoableAsyncAction(action, before: before, {
                    update(newValue)
                })
            }
        )
    }
}
