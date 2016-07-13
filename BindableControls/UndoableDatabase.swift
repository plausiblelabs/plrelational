//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import libRelational
import Binding

public class UndoableDatabase {
    
    private let db: TransactionalDatabase
    private let undoManager: UndoManager
    
    public init(db: TransactionalDatabase, undoManager: UndoManager) {
        self.db = db
        self.undoManager = undoManager
    }
    
    public func performUndoableAction(name: String, before: ChangeLoggingDatabaseSnapshot?, _ transactionFunc: Void -> Void) {
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
    public func bidiProperty<T: Equatable>(relation: Relation, action: String, get: Relation -> T, set: T -> Void) -> ReadWriteProperty<T> {
        return relation.property(mutationConfig(action, set), relationToValue: get)
    }

    /// Note: `set` will be called in the context of a database transaction.
    public func bidiProperty<T: Equatable>(relation: Relation, action: String, get: Relation -> T?, set: T? -> Void) -> ReadWriteProperty<T?> {
        return relation.property(mutationConfig(action, set), relationToValue: get)
    }

    private func mutationConfig<T>(action: String, _ set: T -> Void) -> RelationMutationConfig<T> {
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
    
    /// Note: `set` will be called in the context of a database transaction.
    public func asyncBidiProperty<T>(relation: Relation, action: String, get: Relation -> T, set: T -> Void) -> AsyncReadWriteProperty<T> {
        return relation.asyncProperty(asyncMutationConfig(action, set), relationToValue: get)
    }
    
    private func asyncMutationConfig<T>(action: String, _ set: T -> Void) -> RelationMutationConfig<T> {
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
}
