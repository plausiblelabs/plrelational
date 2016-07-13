//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation


public final class UpdateManager: PerThreadInstance {
    private var pendingUpdates: [Update] = []
    private var observedInfo: ObjectDictionary<AnyObject, ObservedRelationInfo> = [:]
    
    private var executionTimer: CFRunLoopTimer?
    
    public init() {}
    
    public func registerUpdate(relation: Relation, query: SelectExpression, newValues: Row) {
        pendingUpdates.append(.Update(relation, query, newValues))
        sendWillChange(relation)
        scheduleExecutionIfNeeded()
    }
    
    public func registerAdd(relation: TransactionalDatabase.TransactionalRelation, row: Row) {
        pendingUpdates.append(.Add(relation, row))
        sendWillChange(relation)
        scheduleExecutionIfNeeded()
    }
    
    public func registerDelete(relation: TransactionalDatabase.TransactionalRelation, query: SelectExpression) {
        pendingUpdates.append(.Delete(relation, query))
        sendWillChange(relation)
        scheduleExecutionIfNeeded()
    }
    
    public func observe(relation: Relation, observer: AsyncRelationObserver) {
        guard let obj = relation as? AnyObject else { return }
        let info = observedInfo.getOrCreate(obj, defaultValue: ObservedRelationInfo(derivative: RelationDifferentiator(relation: relation).computeDerivative()))
        info.addObserver(observer)
    }
    
    private func sendWillChange(relation: Relation) {
        QueryPlanner.visitRelationTree([(relation, ())], { relation, _, _ in
            guard let relationObject = relation as? AnyObject where !(relation is IntermediateRelation) else { return }
            
            for (observedRelation, info) in observedInfo {
                for variable in info.derivative.allVariables {
                    if relationObject === variable {
                        info.observers.mutatingForEach({
                            if !$0.didSendWillChange {
                                $0.observer.relationWillChange(observedRelation as! Relation)
                                $0.didSendWillChange = true
                            }
                        })
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
        
        let updates = pendingUpdates
        pendingUpdates = []
        
        var databases: ObjectSet<TransactionalDatabase> = []
        var removals: [Void -> Void] = []
        for (observedRelationObj, info) in observedInfo {
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
        
        for (observedRelationObj, info) in observedInfo {
            let relation = observedRelationObj as! Relation
            let change = info.derivative.change
            
            var pendingCount = 0
            var doneCount = 0
            func sendDidChangeIfNeeded() {
                if doneCount == pendingCount {
                    info.observers.mutatingForEach({
                        $0.observer.relationDidChange(relation)
                        $0.didSendWillChange = false
                    })
                }
            }
            
            if let added = change.added {
                added.asyncBulkRows({ result in
                    switch result {
                    case .Ok(let rows) where rows.isEmpty:
                        doneCount += 1
                        sendDidChangeIfNeeded()
                    case .Ok(let rows):
                        for observerEntry in info.observers {
                            observerEntry.observer.relationAddedRows(relation, rows: rows)
                        }
                    case .Err(let err):
                        fatalError("Don't know how to deal with errors yet. \(err)")
                    }
                })
                pendingCount += 1
            }
            if let removed = change.removed {
                removed.asyncBulkRows({ result in
                    switch result {
                    case .Ok(let rows) where rows.isEmpty:
                        doneCount += 1
                        sendDidChangeIfNeeded()
                    case .Ok(let rows):
                        for observerEntry in info.observers {
                            observerEntry.observer.relationAddedRows(relation, rows: rows)
                        }
                    case .Err(let err):
                        fatalError("Don't know how to deal with errors yet. \(err)")
                    }
                })
            }
            sendDidChangeIfNeeded()
        }
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
        var observers: [ObserverEntry] = []
        
        init(derivative: RelationDerivative) {
            self.derivative = derivative
        }
        
        func addObserver(observer: AsyncRelationObserver) {
            observers.append(.init(observer: observer, didSendWillChange: false))
        }
    }
}

public protocol AsyncRelationObserver {
    func relationWillChange(relation: Relation)
    func relationAddedRows(relation: Relation, rows: Set<Row>)
    func relationRemovedRows(relation: Relation, rows: Set<Row>)
    func relationDidChange(relation: Relation)
}
