//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

public typealias RowChange = NegativeSet<Row>

/// There are two fundamental ways to asynchronously observe relations: change observation and content observation.
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
    func relationWillChange(_ relation: Relation)
    func relationAddedRows(_ relation: Relation, rows: Set<Row>)
    func relationRemovedRows(_ relation: Relation, rows: Set<Row>)
    func relationError(_ relation: Relation, error: RelationError)
    func relationDidChange(_ relation: Relation)
}

/// :nodoc: Implementation detail (will be made non-public eventually)
extension AsyncManager {
    public func observe(_ relation: Relation, observer: AsyncRelationChangeCoalescedObserver, context: DispatchContext? = nil) -> ObservationRemover {
        class ShimObserver: AsyncRelationChangeObserver {
            let coalescedObserver: DispatchContextWrapped<AsyncRelationChangeCoalescedObserver>
            var coalescedChanges = RowChange()
            var error: RelationError?
            
            init(coalescedObserver: DispatchContextWrapped<AsyncRelationChangeCoalescedObserver>) {
                self.coalescedObserver = coalescedObserver
            }
            
            func relationWillChange(_ relation: Relation) {
                coalescedObserver.withWrapped({ $0.relationWillChange(relation) })
            }
            
            func relationAddedRows(_ relation: Relation, rows: Set<Row>) {
                coalescedChanges.unionInPlace(rows)
            }
            
            func relationRemovedRows(_ relation: Relation, rows: Set<Row>) {
                coalescedChanges.subtractInPlace(rows)
            }
            
            func relationError(_ relation: Relation, error: RelationError) {
                self.error = error
            }
            
            func relationDidChange(_ relation: Relation) {
                let result = error.map(Result.Err) ?? .Ok(coalescedChanges)
                coalescedChanges.removeAll()
                coalescedObserver.withWrapped({ $0.relationDidChange(relation, result: result) })
            }
        }
        
        let wrappedObserver = DispatchContextWrapped(context: context ?? runloopDispatchContext(), wrapped: observer)
        let shimObserver = ShimObserver(coalescedObserver: wrappedObserver)
        return self.observe(relation, observer: shimObserver, context: DirectDispatchContext())
    }
}

public protocol AsyncRelationChangeCoalescedObserver {
    func relationWillChange(_ relation: Relation)
    func relationDidChange(_ relation: Relation, result: Result<RowChange, RelationError>)
}

public extension Relation {
    
    // MARK: Observation
    
    func addAsyncObserver(_ observer: AsyncRelationChangeObserver) -> AsyncManager.ObservationRemover {
        return AsyncManager.currentInstance.observe(self, observer: observer)
    }
    
    func addAsyncObserver(_ observer: AsyncRelationChangeCoalescedObserver) -> AsyncManager.ObservationRemover {
        return AsyncManager.currentInstance.observe(self, observer: observer)
    }
}

public protocol AsyncRelationContentObserver {
    func relationWillChange(_ relation: Relation)
    func relationNewContents(_ relation: Relation, rows: Set<Row>)
    func relationError(_ relation: Relation, error: RelationError)
    func relationDidChange(_ relation: Relation)
}

/// :nodoc: Implementation detail (will be made non-public eventually)
extension AsyncManager {
    public func observe<T: AsyncRelationContentCoalescedObserver>(_ relation: Relation, observer: T, context: DispatchContext? = nil, postprocessor: @escaping (Set<Row>) -> T.PostprocessingOutput) -> ObservationRemover {
        
        let wrappedObserver = DispatchContextWrapped(context: context ?? runloopDispatchContext(), wrapped: observer)
        let shimObserver = ShimContentObserver(coalescedObserver: wrappedObserver, postprocessor: postprocessor)
        return self.observe(relation, observer: shimObserver, context: DirectDispatchContext())
    }
}

public protocol AsyncRelationContentCoalescedObserver {
    associatedtype PostprocessingOutput
    
    func relationWillChange(_ relation: Relation)
    func relationDidChange(_ relation: Relation, result: Result<PostprocessingOutput, RelationError>)
}


public extension Relation {
    func addAsyncObserver(_ observer: AsyncRelationContentObserver) -> AsyncManager.ObservationRemover {
        return AsyncManager.currentInstance.observe(self, observer: observer)
    }
    
    /// If desired, this method can be used to supply a postprocessor function which runs in the background after the rows
    /// are accumulated but before results are sent to the observer. This postprocessor can, for example, sort the rows and
    /// produce an array which is then passed to the observer.
    func addAsyncObserver<T: AsyncRelationContentCoalescedObserver>(_ observer: T, postprocessor: @escaping (Set<Row>) -> T.PostprocessingOutput) -> AsyncManager.ObservationRemover {
        return AsyncManager.currentInstance.observe(self, observer: observer, postprocessor: postprocessor)
    }
    
    /// This method may be used when the observer just wants a raw set of rows to be delivered, without any postprocessing.
    func addAsyncObserver<T: AsyncRelationContentCoalescedObserver>(_ observer: T) -> AsyncManager.ObservationRemover where T.PostprocessingOutput == Set<Row> {
        return AsyncManager.currentInstance.observe(self, observer: observer, postprocessor: { $0 })
    }
}

public extension Relation {
    
    // MARK: Updates
    
    func asyncUpdate(_ query: SelectExpression, newValues: Row) {
        AsyncManager.currentInstance.registerUpdate(self, query: query, newValues: newValues)
    }
}

/// :nodoc: Implementation detail (will be made non-public eventually)
/// Returns a postprocessing function which sorts the rows in ascending order based on the value each row has for `attribute`.
public func sortByAttribute(_ attribute: Attribute) -> ((Set<Row>) -> [Row]) {
    return {
        $0.sorted(by: { $0[attribute] < $1[attribute] })
    }
}

private class ShimContentObserver<T: AsyncRelationContentCoalescedObserver>: AsyncRelationContentObserver {
    let coalescedObserver: DispatchContextWrapped<T>
    let postprocess: (Set<Row>) -> T.PostprocessingOutput
    var coalescedRows: Set<Row> = []
    var error: RelationError?
    var changing = false
    
    init(coalescedObserver: DispatchContextWrapped<T>, postprocessor: @escaping (Set<Row>) -> T.PostprocessingOutput) {
        self.coalescedObserver = coalescedObserver
        self.postprocess = postprocessor
    }
    
    func relationWillChange(_ relation: Relation) {
        precondition(!changing)
        changing = true
        
        coalescedObserver.withWrapped({ $0.relationWillChange(relation) })
    }
    
    func relationNewContents(_ relation: Relation, rows: Set<Row>) {
        precondition(changing)
        
        coalescedRows.formUnion(rows)
    }
    
    func relationError(_ relation: Relation, error: RelationError) {
        precondition(changing)
        
        self.error = error
    }
    
    func relationDidChange(_ relation: Relation) {
        precondition(changing)
        changing = false
        
        let result = error.map(Result.Err) ?? .Ok(coalescedRows)
        coalescedRows.removeAll()
        
        let postprocessedResult = result.map(postprocess)
        coalescedObserver.withWrapped({ $0.relationDidChange(relation, result: postprocessedResult) })
    }
}
