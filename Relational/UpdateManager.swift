//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation


public final class UpdateManager: PerThreadInstance {
    public typealias ObservationRemover = Void -> Void
    
    private var pendingUpdates: [Update] = []
    private var observedInfo: ObjectDictionary<AnyObject, ObservedRelationInfo> = [:]
    
    private var isExecuting = false
    private var executionTimer: CFRunLoopTimer?
    
    public init() {}
    
    public func registerUpdate(relation: Relation, query: SelectExpression, newValues: Row) {
        pendingUpdates.append(.Update(relation, query, newValues))
        registerChange(relation)
    }
    
    public func registerAdd(relation: TransactionalDatabase.TransactionalRelation, row: Row) {
        pendingUpdates.append(.Add(relation, row))
        registerChange(relation)
    }
    
    public func registerDelete(relation: TransactionalDatabase.TransactionalRelation, query: SelectExpression) {
        pendingUpdates.append(.Delete(relation, query))
        registerChange(relation)
    }
    
    public func registerRestoreSnapshot(database: TransactionalDatabase, snapshot: ChangeLoggingDatabaseSnapshot) {
        pendingUpdates.append(.RestoreSnapshot(database, snapshot))
        for (_, relation) in database.relations {
            registerChange(relation)
        }
    }
    
    public func observe(relation: Relation, observer: AsyncRelationObserver) -> ObservationRemover {
        guard let obj = relation as? AnyObject else { return {} }
        
        let info = observedInfo.getOrCreate(obj, defaultValue: ObservedRelationInfo(derivative: RelationDifferentiator(relation: relation).computeDerivative()))
        let id = info.addObserver(observer)
        
        return {
            info.observers[id] = nil
            if info.observers.isEmpty {
                self.observedInfo[obj] = nil
            }
        }
    }
    
    private func registerChange(relation: Relation) {
        if !isExecuting {
            sendWillChange(relation)
            scheduleExecutionIfNeeded()
        }
    }
    
    private func sendWillChange(relation: Relation) {
        QueryPlanner.visitRelationTree([(relation, ())], { relation, _, _ in
            guard let relationObject = relation as? AnyObject where !(relation is IntermediateRelation) else { return }
            
            for (observedRelation, info) in observedInfo {
                for variable in info.derivative.allVariables {
                    if relationObject === variable {
                        var willChangeObservers: [AsyncRelationObserver] = []
                        info.observers.mutatingForEach({
                            if !$0.didSendWillChange {
                                $0.didSendWillChange = true
                                willChangeObservers.append($0.observer)
                            }
                        })
                        for observer in willChangeObservers {
                            observer.relationWillChange(observedRelation as! Relation)
                        }
                    }
                }
            }
        })
    }
    
    private func scheduleExecutionIfNeeded() {
        if executionTimer == nil {
            executionTimer = CFRunLoopTimerCreateWithHandler(nil, 0, 0, 0, 0, { _ in
                self.execute()
            })
            CFRunLoopAddTimer(CFRunLoopGetCurrent(), executionTimer, kCFRunLoopCommonModes)
        }
    }
    
    private func execute() {
        CFRunLoopTimerInvalidate(executionTimer)
        executionTimer = nil
        isExecuting = true
        executeBody()
    }
    
    private func executeBody() {
        // Apply all pending updates asynchronously. Update work is done in the background, with callbacks onto
        // this runloop for synchronization and notifying observers.
        let updates = pendingUpdates
        pendingUpdates = []
        
        let observedInfo = self.observedInfo
        
        // Wrap up the work needed to call back into the originating runloop.
        let runloop = CFRunLoopGetCurrent()
        func callback(f: Void -> Void) {
            CFRunLoopPerformBlock(runloop, kCFRunLoopCommonModes, f)
            CFRunLoopWakeUp(runloop)
        }
        
        // Run updates in the background.
        dispatch_async(dispatch_get_global_queue(0, 0), {
            // Walk through all the observers. Observe changes on all relevant variables and update
            // observer derivatives with those changes as they come in. Also locate all
            // TransactionalDatabases referenced within so we can begin and end transactions.
            var databases: ObjectSet<TransactionalDatabase> = []
            var removals: [Void -> Void] = []
            for (_, info) in observedInfo {
                let derivative = info.derivative
                for variable in derivative.allVariables {
                    let removal = variable.addChangeObserver({
                        let copiedAddResult = $0.added.map(ConcreteRelation.copyRelation)
                        let copiedRemoveResult = $0.removed.map(ConcreteRelation.copyRelation)
                        
                        if let err = copiedAddResult?.err ?? copiedRemoveResult?.err {
                            fatalError("Error copying changes, don't know how to handle that yet: \(err)")
                        }
                        
                        let copiedChange = RelationChange(added: copiedAddResult?.ok, removed: copiedRemoveResult?.ok)
                        derivative.addChange(copiedChange, toVariable: variable)
                    })
                    removals.append(removal)
                    
                    if let transactionalRelation = variable as? TransactionalDatabase.TransactionalRelation,
                           db = transactionalRelation.db {
                        databases.insert(db)
                    }
                }
            }
            
            // Wrap everything up in a transaction.
            // TODO: this doesn't really work when there's more than one database, even though we sort of
            // pretend like it does. Fix that? Explicitly limit it to one database?
            for db in databases {
                db.beginTransaction()
            }
            
            // Apply the actual updates to the relations.
            for update in updates {
                let error: RelationError?
                switch update {
                case .Update(let relation, let query, let newValues):
                    var mutableRelation = relation
                    let result = mutableRelation.update(query, newValues: newValues)
                    error = result.err
                case .Add(let relation, let row):
                    let result = relation.add(row)
                    error = result.err
                case .Delete(let relation, let query):
                    let result = relation.delete(query)
                    error = result.err
                case .RestoreSnapshot(let database, let snapshot):
                    if databases.contains(database) {
                        database.endTransaction()
                        database.restoreSnapshot(snapshot)
                        database.beginTransaction()
                    } else {
                        database.restoreSnapshot(snapshot)
                    }
                    error = nil
                }
                
                if let error = error {
                    fatalError("Don't know how to deal with update errors yet, got error \(error)")
                }
            }
            
            // And end the transaction.
            for db in databases {
                db.endTransaction()
            }
            
            // All changes are done, so remove the observations registered above.
            for removal in removals {
                removal()
            }
            
            // We'll be doing a bunch of async work to notify observers. Use a dispatch group to figure out when it's all done.
            let doneGroup = dispatch_group_create()
            
            // Go through all the observers and notify them.
            for (observedRelationObj, info) in observedInfo {
                let relation = observedRelationObj as! Relation
                let change = info.derivative.change
                
                // If there are additions, then iterate over them and send them to the observer. Iteration is started in the
                // original runloop, which ensures that the callbacks happen there too.
                if let added = change.added {
                    dispatch_group_enter(doneGroup)
                    callback({
                        added.asyncBulkRows({ result in
                            switch result {
                            case .Ok(let rows) where rows.isEmpty:
                                dispatch_group_leave(doneGroup)
                            case .Ok(let rows):
                                for observerEntry in info.observers.values {
                                    observerEntry.observer.relationAddedRows(relation, rows: rows)
                                }
                            case .Err(let err):
                                fatalError("Don't know how to deal with errors yet. \(err)")
                            }
                        })
                    })
                }
                // Do the same if there are removals.
                if let removed = change.removed {
                    dispatch_group_enter(doneGroup)
                    callback({
                        removed.asyncBulkRows({ result in
                            switch result {
                            case .Ok(let rows) where rows.isEmpty:
                                dispatch_group_leave(doneGroup)
                            case .Ok(let rows):
                                for observerEntry in info.observers.values {
                                    observerEntry.observer.relationRemovedRows(relation, rows: rows)
                                }
                            case .Err(let err):
                                fatalError("Don't know how to deal with errors yet. \(err)")
                            }
                        })
                    })
                }
            }
            
            // Wait until done. If there are no changes then this will execute immediately. Otherwise it will execute
            // when all the iteration above is complete.
            dispatch_group_notify(doneGroup, dispatch_get_global_queue(0, 0), {
                callback({
                    // If new pending updates came in while we were doing our thing, then go back to the top
                    // and start over, applying those updates too.
                    if !self.pendingUpdates.isEmpty {
                        self.executeBody()
                    } else {
                        // Otherwise, terminate the execution. Reset observers and send didChange to them.
                        self.isExecuting = false
                        for (observedRelationObj, info) in observedInfo {
                            info.derivative.clearVariables()
                            
                            let relation = observedRelationObj as! Relation
                            var observersWithWillChange: [AsyncRelationObserver] = []
                            info.observers.mutatingForEach({
                                if $0.didSendWillChange {
                                    $0.didSendWillChange = false
                                    observersWithWillChange.append($0.observer)
                                }
                            })
                            for observer in observersWithWillChange {
                                observer.relationDidChange(relation)
                            }
                        }
                    }
                })
            })
        })
    }
}

extension UpdateManager {
    private enum Update {
        case Update(Relation, SelectExpression, Row)
        case Add(TransactionalDatabase.TransactionalRelation, Row)
        case Delete(TransactionalDatabase.TransactionalRelation, SelectExpression)
        case RestoreSnapshot(TransactionalDatabase, ChangeLoggingDatabaseSnapshot)
    }
    
    private class ObservedRelationInfo {
        struct ObserverEntry {
            var observer: AsyncRelationObserver
            var didSendWillChange: Bool
        }
        
        let derivative: RelationDerivative
        var observers: [UInt64: ObserverEntry] = [:]
        var currentObserverID: UInt64 = 0
        
        init(derivative: RelationDerivative) {
            self.derivative = derivative
        }
        
        func addObserver(observer: AsyncRelationObserver) -> UInt64 {
            currentObserverID += 1
            observers[currentObserverID] = ObserverEntry(observer: observer, didSendWillChange: false)
            return currentObserverID
        }
    }
}

public protocol AsyncRelationObserver {
    func relationWillChange(relation: Relation)
    func relationAddedRows(relation: Relation, rows: Set<Row>)
    func relationRemovedRows(relation: Relation, rows: Set<Row>)
    func relationDidChange(relation: Relation)
}

extension UpdateManager {
    public func observeCoalesced(relation: Relation, observer: AsyncCoalescedRelationObserver) -> ObservationRemover {
        class ShimObserver: AsyncRelationObserver {
            let bulkObserver: AsyncCoalescedRelationObserver
            var coalescedChanges = NegativeSet<Row>()
            
            init(bulkObserver: AsyncCoalescedRelationObserver) {
                self.bulkObserver = bulkObserver
            }
            
            func relationWillChange(relation: Relation) {
                bulkObserver.relationWillChange(relation)
            }
            
            func relationAddedRows(relation: Relation, rows: Set<Row>) {
                coalescedChanges.unionInPlace(rows)
            }
            
            func relationRemovedRows(relation: Relation, rows: Set<Row>) {
                coalescedChanges.subtractInPlace(rows)
            }
            
            func relationDidChange(relation: Relation) {
                bulkObserver.relationDidChange(relation, added: coalescedChanges.added, removed: coalescedChanges.removed)
            }
        }
        
        return self.observe(relation, observer: ShimObserver(bulkObserver: observer))
    }
}

public protocol AsyncCoalescedRelationObserver {
    func relationWillChange(relation: Relation)
    func relationDidChange(relation: Relation, added: Set<Row>, removed: Set<Row>)
}

public extension Relation {
    func addAsyncObserver(observer: AsyncRelationObserver) -> UpdateManager.ObservationRemover {
        return UpdateManager.currentInstance.observe(self, observer: observer)
    }
    
    func addAsyncCoalescedObserver(observer: AsyncCoalescedRelationObserver) -> UpdateManager.ObservationRemover {
        return UpdateManager.currentInstance.observeCoalesced(self, observer: observer)
    }
}

public extension Relation {
    func asyncUpdate(query: SelectExpression, newValues: Row) {
        UpdateManager.currentInstance.registerUpdate(self, query: query, newValues: newValues)
    }
}
