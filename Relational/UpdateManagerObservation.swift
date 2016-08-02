//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation


/// There are two fundamenal ways to asynchronously observe relations: change observation and content observation.
///
/// Change observation provides the deltas for each change. This is useful for things that need to know exactly
/// what changed, perhaps so they can efficiently update some other thing derived from the Relation content.
///
/// Content observation provides the entire Relation content after each change. This is useful for things that don't
/// care about the details of which bits changed, just what the data looks like after the change.
///
/// Change observation is done by implementing AsyncRelationChangeObserver. The observer receives a willChange call
/// any time an asynchronous update is scheduled for a Relation that the target Relation depends on. This happens
/// regardless of whether the scheduled change actually alters the content of the target Relation, because figuring
/// that out is expensive. The addedRows and removedRows methods are called zero or more times each to indicate
/// new or deleted rows. If additional updates are made while this is in progress, the observer may receive redundant
/// additions and removals (e.g. a row is shown as added, then as removed) during the same sequence of calls. When
/// an update cycle is completed, didChange is called, if willChange was previously called.
///
/// Content observation is done by implementing AsyncRelationContentObserver. Like change observers, the observer
/// receives a willChange call for any scheduled change to a dependent Relation. The newContents method is called
/// zero or more times to report the new contents of the target Relation, and finally didChange is called.
///
/// Each type of observer also has a Coalesced variant. In this version, there's only willChange and didChange,
/// where didChange also reports the entire set of deltas (for change observers) or the entire new content of the
/// target Relation (for content observers). This saves observers from buffering everything manually, for observers
/// which need to have everything before they can take any action.

public protocol AsyncRelationChangeObserver {
    func relationWillChange(relation: Relation)
    func relationAddedRows(relation: Relation, rows: Set<Row>)
    func relationRemovedRows(relation: Relation, rows: Set<Row>)
    func relationError(relation: Relation, error: RelationError)
    func relationDidChange(relation: Relation)
}

extension UpdateManager {
    public func observe(relation: Relation, observer: AsyncRelationChangeCoalescedObserver, context: DispatchContext? = nil) -> ObservationRemover {
        class ShimObserver: AsyncRelationChangeObserver {
            static let queueName = "\(ShimObserver.self)"
            
            let coalescedObserver: DispatchContextWrapped<AsyncRelationChangeCoalescedObserver>
            var coalescedChanges = NegativeSet<Row>()
            var error: RelationError?
            
            init(coalescedObserver: DispatchContextWrapped<AsyncRelationChangeCoalescedObserver>) {
                self.coalescedObserver = coalescedObserver
            }
            
            func relationWillChange(relation: Relation) {
                coalescedObserver.withWrapped({ $0.relationWillChange(relation) })
            }
            
            func relationAddedRows(relation: Relation, rows: Set<Row>) {
                coalescedChanges.unionInPlace(rows)
            }
            
            func relationRemovedRows(relation: Relation, rows: Set<Row>) {
                coalescedChanges.subtractInPlace(rows)
            }
            
            func relationError(relation: Relation, error: RelationError) {
                self.error = error
            }
            
            func relationDidChange(relation: Relation) {
                let result = error.map(Result.Err) ?? .Ok(coalescedChanges)
                coalescedChanges.removeAll()
                coalescedObserver.withWrapped({ $0.relationDidChange(relation, result: result) })
            }
        }
        
        let wrappedObserver = DispatchContextWrapped(context: context ?? CFRunLoopGetCurrent(), wrapped: observer)
        let shimObserver = ShimObserver(coalescedObserver: wrappedObserver)
        let queue = DispatchQueueContext(newSerialQueueNamed: ShimObserver.queueName)
        return self.observe(relation, observer: shimObserver, context: queue)
    }
}

public protocol AsyncRelationChangeCoalescedObserver {
    func relationWillChange(relation: Relation)
    func relationDidChange(relation: Relation, result: Result<NegativeSet<Row>, RelationError>)
}

public extension Relation {
    func addAsyncObserver(observer: AsyncRelationChangeObserver) -> UpdateManager.ObservationRemover {
        return UpdateManager.currentInstance.observe(self, observer: observer)
    }
    
    func addAsyncObserver(observer: AsyncRelationChangeCoalescedObserver) -> UpdateManager.ObservationRemover {
        return UpdateManager.currentInstance.observe(self, observer: observer)
    }
}

public protocol AsyncRelationContentObserver {
    func relationWillChange(relation: Relation)
    func relationNewContents(relation: Relation, rows: Set<Row>)
    func relationError(relation: Relation, error: RelationError)
    func relationDidChange(relation: Relation)
}

extension UpdateManager {
    public func observe(relation: Relation, observer: AsyncRelationContentCoalescedObserver, context: DispatchContext? = nil) -> ObservationRemover {
        class ShimObserver: AsyncRelationContentObserver {
            static let queueName = "\(ShimObserver.self)"
            
            let coalescedObserver: DispatchContextWrapped<AsyncRelationContentCoalescedObserver>
            var coalescedRows: Set<Row> = []
            var error: RelationError?
            
            init(coalescedObserver: DispatchContextWrapped<AsyncRelationContentCoalescedObserver>) {
                self.coalescedObserver = coalescedObserver
            }
            
            func relationWillChange(relation: Relation) {
                coalescedObserver.withWrapped({ $0.relationWillChange(relation) })
            }
            
            func relationNewContents(relation: Relation, rows: Set<Row>) {
                coalescedRows.unionInPlace(rows)
            }
            
            func relationError(relation: Relation, error: RelationError) {
                self.error = error
            }
            
            func relationDidChange(relation: Relation) {
                let result = error.map(Result.Err) ?? .Ok(coalescedRows)
                coalescedRows.removeAll()
                coalescedObserver.withWrapped({ $0.relationDidChange(relation, result: result) })
            }
        }
        
        let wrappedObserver = DispatchContextWrapped(context: context ?? CFRunLoopGetCurrent(), wrapped: observer)
        let shimObserver = ShimObserver(coalescedObserver: wrappedObserver)
        let queue = DispatchQueueContext(newSerialQueueNamed: ShimObserver.queueName)
        return self.observe(relation, observer: shimObserver, context: queue)
    }
}

public protocol AsyncRelationContentCoalescedObserver {
    func relationWillChange(relation: Relation)
    func relationDidChange(relation: Relation, result: Result<Set<Row>, RelationError>)
}

public extension Relation {
    func addAsyncObserver(observer: AsyncRelationContentObserver) -> UpdateManager.ObservationRemover {
        return UpdateManager.currentInstance.observe(self, observer: observer)
    }
    
    func addAsyncObserver(observer: AsyncRelationContentCoalescedObserver) -> UpdateManager.ObservationRemover {
        return UpdateManager.currentInstance.observe(self, observer: observer)
    }
}

public extension Relation {
    func asyncUpdate(query: SelectExpression, newValues: Row) {
        UpdateManager.currentInstance.registerUpdate(self, query: query, newValues: newValues)
    }
}
