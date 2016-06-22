//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

public protocol RelationObserver {
    func transactionBegan()
    func relationChanged(relation: Relation, change: RelationChange)
    func transactionEnded()
}

class WeakRelationObserverProxy: RelationObserver {
    private weak var target: protocol<RelationObserver, AnyObject>?
    private var targetRemoval: Void -> Void = { fatalError("Proxy deallocated, but target removal function never set.") }
    private var relationRemoval: Void -> Void = { fatalError("Observer method called, but relation removal function never set.") }
    
    init(target: protocol<RelationObserver, AnyObject>) {
        self.target = target
        targetRemoval = ObserveDeallocation(target, { [weak self] in
            self?.relationRemoval()
        })
    }
    
    func registerOn(observee: Relation, kinds: [RelationObservationKind]) {
        relationRemoval = observee.addChangeObserver(self, kinds: kinds)
    }
    
    func transactionBegan() {
        getTargetOrRemove()?.transactionBegan()
    }
    
    func relationChanged(relation: Relation, change: RelationChange) {
        getTargetOrRemove()?.relationChanged(relation, change: change)
    }
    
    func transactionEnded() {
        getTargetOrRemove()?.transactionEnded()
    }
    
    private func getTargetOrRemove() -> RelationObserver? {
        if let target = target {
            return target
        } else {
            relationRemoval()
            return nil
        }
    }
}

struct SimpleRelationObserverProxy: RelationObserver {
    var f: RelationChange -> Void
    func transactionBegan() {}
    func relationChanged(relation: Relation, change: RelationChange) {
        f(change)
    }
    func transactionEnded() {}
}
