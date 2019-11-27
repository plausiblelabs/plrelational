//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
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

extension TransactionalRelation {
    
    /// Returns an AsyncReadWriteProperty that delivers a set of all RelationValues for the single attribute
    /// and updates the relation when new values are provided to the property.
    public func undoableAllRelationValues(_ db: UndoableDatabase, _ action: String) -> AsyncReadWriteProperty<Set<RelationValue>> {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        return db.bidiProperty(
            action: action,
            signal: self.allRelationValues(),
            update: { self.asyncReplaceValues(Array($0)) }
        )
    }
}

extension Relation {

    /// Returns an AsyncReadWriteProperty that delivers a single string value if there is exactly
    /// one row in the relation (otherwise an empty string), and updates the relation when a new
    /// string value is provided to the property.
    public func undoableOneString(_ db: UndoableDatabase, _ action: String, initialValue: String? = nil) -> AsyncReadWriteProperty<String> {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        return db.bidiProperty(
            action: action,
            signal: self.oneString(initialValue: initialValue),
            update: { self.asyncUpdateString($0) }
        )
    }
    
    /// Returns an AsyncReadWriteProperty that delivers a single value (transformed from a string)
    /// and updates the relation with a new string (transformed from a value of type `T`) when one
    /// is provided to the property.
    public func undoableTransformedString<T>(_ db: UndoableDatabase,
                                             _ action: String, initialValue: String? = nil,
                                             fromString: @escaping (String) -> T,
                                             toString: @escaping (T) -> String) -> AsyncReadWriteProperty<T>
    {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        return db.bidiProperty(
            action: action,
            signal: self.oneString(initialValue: initialValue).map(fromString),
            update: { value in
                self.asyncUpdateString(toString(value))
            }
        )
    }
}
