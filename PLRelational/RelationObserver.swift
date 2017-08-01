//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

/// :nodoc:
public protocol RelationObserver {
    func transactionBegan()
    func relationChanged(_ relation: Relation, change: RelationChange)
    func transactionEnded()
}

class WeakRelationObserverProxy: RelationObserver {
    fileprivate weak var target: (RelationObserver & AnyObject)?
    fileprivate var targetRemoval: (Void) -> Void = { fatalError("Proxy deallocated, but target removal function never set.") }
    fileprivate var relationRemoval: (Void) -> Void = { fatalError("Observer method called, but relation removal function never set.") }
    
    init(target: RelationObserver & AnyObject) {
        self.target = target
        targetRemoval = ObserveDeallocation(target, { [weak self] in
            self?.relationRemoval()
        })
    }
    
    func registerOn(_ observee: Relation, kinds: [RelationObservationKind]) {
        relationRemoval = observee.addChangeObserver(self, kinds: kinds)
    }
    
    func transactionBegan() {
        getTargetOrRemove()?.transactionBegan()
    }
    
    func relationChanged(_ relation: Relation, change: RelationChange) {
        getTargetOrRemove()?.relationChanged(relation, change: change)
    }
    
    func transactionEnded() {
        getTargetOrRemove()?.transactionEnded()
    }
    
    fileprivate func getTargetOrRemove() -> RelationObserver? {
        if let target = target {
            return target
        } else {
            relationRemoval()
            return nil
        }
    }
}

struct SimpleRelationObserverProxy: RelationObserver {
    var f: (RelationChange) -> Void
    func transactionBegan() {}
    func relationChanged(_ relation: Relation, change: RelationChange) {
        f(change)
    }
    func transactionEnded() {}
}
