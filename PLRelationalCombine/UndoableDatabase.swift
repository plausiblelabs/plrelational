//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import PLRelational

public class UndoableDatabase {
    
    private let db: TransactionalDatabase
    private let undoManager: UndoManager

    public init(db: TransactionalDatabase, undoManager: UndoManager) {
        self.db = db
        self.undoManager = undoManager
    }
    
    public func performUndoableAction(_ name: String, before: TransactionalDatabaseSnapshot? = nil, _ transactionFunc: @escaping () -> Void) {
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
}
