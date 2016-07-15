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
        let updates = pendingUpdates
        pendingUpdates = []
        
        let observedInfo = self.observedInfo
        
        let runloop = CFRunLoopGetCurrent()
        func callback(f: Void -> Void) {
            CFRunLoopPerformBlock(runloop, kCFRunLoopCommonModes, f)
            CFRunLoopWakeUp(runloop)
        }
        
        dispatch_async(dispatch_get_global_queue(0, 0), {
            var databases: ObjectSet<TransactionalDatabase> = []
            var removals: [Void -> Void] = []
            for (_, info) in observedInfo {
                let derivative = info.derivative
                for variable in derivative.allVariables {
                    let removal = variable.addChangeObserver({
                        derivative.setChange($0, forVariable: variable)
                    })
                    removals.append(removal)
                    
                    if let transactionalRelation = variable as? TransactionalDatabase.TransactionalRelation {
                        databases.insert(transactionalRelation.db!)
                    }
                }
            }
            
            for db in databases {
                db.beginTransaction()
            }
            
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
                }
                
                if let error = error {
                    fatalError("Don't know how to deal with update errors yet, got error \(error)")
                }
            }
            
            for db in databases {
                db.endTransaction()
            }
            
            for removal in removals {
                removal()
            }
            
            let doneGroup = dispatch_group_create()
            
            for (observedRelationObj, info) in observedInfo {
                let relation = observedRelationObj as! Relation
                let change = info.derivative.change
                
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
            
            dispatch_group_notify(doneGroup, dispatch_get_global_queue(0, 0), {
                callback({
                    if !self.pendingUpdates.isEmpty {
                        self.executeBody()
                    } else {
                        self.isExecuting = false
                        for (observedRelationObj, info) in observedInfo {
                            let relation = observedRelationObj as! Relation
                            info.observers.mutatingForEach({
                                $0.didSendWillChange = false
                            })
                            for observerEntry in info.observers.values {
                                observerEntry.observer.relationDidChange(relation)
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
    public func observeBulk(relation: Relation, observer: AsyncBulkRelationObserver) -> ObservationRemover {
        class ShimObserver: AsyncRelationObserver {
            let bulkObserver: AsyncBulkRelationObserver
            var added: Set<Row> = []
            var removed: Set<Row> = []
            
            init(bulkObserver: AsyncBulkRelationObserver) {
                self.bulkObserver = bulkObserver
            }
            
            func relationWillChange(relation: Relation) {
                bulkObserver.relationWillChange(relation)
            }
            
            func relationAddedRows(relation: Relation, rows: Set<Row>) {
                let new = rows.subtract(removed)
                added.unionInPlace(new)
                removed.subtractInPlace(rows)
            }
            
            func relationRemovedRows(relation: Relation, rows: Set<Row>) {
                let gone = rows.subtract(added)
                removed.unionInPlace(gone)
                added.subtractInPlace(rows)
            }
            
            func relationDidChange(relation: Relation) {
                bulkObserver.relationDidChange(relation, added: added, removed: removed)
            }
        }
        
        return self.observe(relation, observer: ShimObserver(bulkObserver: observer))
    }
}

public protocol AsyncBulkRelationObserver {
    func relationWillChange(relation: Relation)
    func relationDidChange(relation: Relation, added: Set<Row>, removed: Set<Row>)
}
