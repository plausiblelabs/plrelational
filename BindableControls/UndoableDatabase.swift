//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import libRelational
import Binding

open class UndoableDatabase {
    
    private let db: TransactionalDatabase
    private let undoManager: UndoManager
    
    public init(db: TransactionalDatabase, undoManager: UndoManager) {
        self.db = db
        self.undoManager = undoManager
    }
    
    open func performUndoableAction(_ name: String, before: ChangeLoggingDatabaseSnapshot?, _ transactionFunc: (Void) -> Void) {
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
    open func bidiProperty<T: Equatable>(_ relation: Relation, action: String, get: @escaping (Relation) -> T, set: @escaping (T) -> Void) -> ReadWriteProperty<T> {
        return relation.property(mutationConfig(action, set), relationToValue: get)
    }

    /// Note: `set` will be called in the context of a database transaction.
    open func bidiProperty<T: Equatable>(_ relation: Relation, action: String, get: @escaping (Relation) -> T?, set: @escaping (T?) -> Void) -> ReadWriteProperty<T?> {
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
    
    open func performUndoableAsyncAction(_ name: String, before: ChangeLoggingDatabaseSnapshot?, _ transactionFunc: (Void) -> Void) {
        let before = before ?? db.takeSnapshot()
        // TODO: Need explicit transaction here
        //db.transaction(transactionFunc)
        transactionFunc()
        let after = db.takeSnapshot()
        
        undoManager.registerChange(
            name: name,
            perform: false,
            forward: {
                self.db.asyncRestoreSnapshot(after)
            },
            backward: {
                self.db.asyncRestoreSnapshot(before)
            }
        )
    }
    
    open func asyncBidiProperty<T>(_ relation: Relation, action: String, signal: Signal<T>, update: @escaping (T) -> Void) -> AsyncReadWriteProperty<T> {
        return relation.asyncProperty(asyncMutationConfig(action, update), { _ in signal })
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
