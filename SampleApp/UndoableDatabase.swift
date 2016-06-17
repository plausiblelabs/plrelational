//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import libRelational
import Binding

class UndoableDatabase {
    
    private let db: TransactionalDatabase
    private let undoManager: UndoManager
    
    init(db: TransactionalDatabase, undoManager: UndoManager) {
        self.db = db
        self.undoManager = undoManager
    }
    
    func performUndoableAction(name: String, before: ChangeLoggingDatabaseSnapshot?, _ transactionFunc: Void -> Void) {
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
    func observe<T: Equatable>(relation: Relation, action: String, get: Relation -> T, set: T -> Void) -> MutableObservableValue<T> {
        return relation.mutableObservable(mutationConfig(action, set), relationToValue: get)
    }
    
    /// Note: `set` will be called in the context of a database transaction.
    func observe<T: Equatable>(relation: Relation, action: String, get: Relation -> T?, set: T? -> Void) -> MutableObservableValue<T?> {
        return relation.mutableObservable(mutationConfig(action, set), relationToValue: get)
    }

    /// Note: `set` will be called in the context of a database transaction.
    func bidiProperty<T: Equatable>(relation: Relation, action: String, get: Relation -> T, set: T -> Void) -> BidiProperty<T> {
        return relation.bidiProperty(mutationConfig(action, set), relationToValue: get)
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
}
