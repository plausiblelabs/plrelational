//
//  UndoableDatabase.swift
//  Relational
//
//  Created by Chris Campbell on 5/26/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Foundation
import libRelational

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
    func bidiBinding<T>(relation: Relation, action: String, get: Relation -> T, set: T -> Void) -> BidiValueBinding<T> {
        let config = RelationBidiConfig(
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
        return relation.bindBidi(config, relationToValue: get)
    }
}
