//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//


public protocol AsyncRelationObserver {
    func relationWillChange(relation: Relation)
    func relationAddedRows(relation: Relation, rows: Set<Row>)
    func relationRemovedRows(relation: Relation, rows: Set<Row>)
    func relationDidChange(relation: Relation)
}

extension UpdateManager {
    public func observeCoalesced(relation: Relation, observer: AsyncCoalescedRelationObserver) -> ObservationRemover {
        class ShimObserver: AsyncRelationObserver {
            let coalescedObserver: AsyncCoalescedRelationObserver
            var coalescedChanges = NegativeSet<Row>()
            
            init(coalescedObserver: AsyncCoalescedRelationObserver) {
                self.coalescedObserver = coalescedObserver
            }
            
            func relationWillChange(relation: Relation) {
                coalescedObserver.relationWillChange(relation)
            }
            
            func relationAddedRows(relation: Relation, rows: Set<Row>) {
                coalescedChanges.unionInPlace(rows)
            }
            
            func relationRemovedRows(relation: Relation, rows: Set<Row>) {
                coalescedChanges.subtractInPlace(rows)
            }
            
            func relationDidChange(relation: Relation) {
                coalescedObserver.relationDidChange(relation, added: coalescedChanges.added, removed: coalescedChanges.removed)
            }
        }
        
        return self.observe(relation, observer: ShimObserver(coalescedObserver: observer))
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

public protocol AsyncUpdateRelationObserver {
    func relationWillChange(relation: Relation)
    func relationNewContents(relation: Relation, rows: Set<Row>)
    func relationDidChange(relation: Relation)
}

extension UpdateManager {
    public func observeCoalesced(relation: Relation, observer: AsyncCoalescedUpdateRelationObserver) -> ObservationRemover {
        class ShimObserver: AsyncUpdateRelationObserver {
            let coalescedObserver: AsyncCoalescedUpdateRelationObserver
            var coalescedRows: Set<Row> = []
            
            init(coalescedObserver: AsyncCoalescedUpdateRelationObserver) {
                self.coalescedObserver = coalescedObserver
            }
            
            func relationWillChange(relation: Relation) {
                coalescedObserver.relationWillChange(relation)
            }
            
            func relationNewContents(relation: Relation, rows: Set<Row>) {
                coalescedRows.unionInPlace(rows)
            }
            
            func relationDidChange(relation: Relation) {
                coalescedObserver.relationDidChange(relation, rows: coalescedRows)
            }
        }
        
        return self.observe(relation, observer: ShimObserver(coalescedObserver: observer))
    }
}

public protocol AsyncCoalescedUpdateRelationObserver {
    func relationWillChange(relation: Relation)
    func relationDidChange(relation: Relation, rows: Set<Row>)
}

public extension Relation {
    func addAsyncObserver(observer: AsyncUpdateRelationObserver) -> UpdateManager.ObservationRemover {
        return UpdateManager.currentInstance.observe(self, observer: observer)
    }
    
    func addAsyncCoalescedObserver(observer: AsyncCoalescedUpdateRelationObserver) -> UpdateManager.ObservationRemover {
        return UpdateManager.currentInstance.observeCoalesced(self, observer: observer)
    }
}

public extension Relation {
    func asyncUpdate(query: SelectExpression, newValues: Row) {
        UpdateManager.currentInstance.registerUpdate(self, query: query, newValues: newValues)
    }
}
