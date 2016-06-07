
public protocol RelationObserver {
    func transactionBegan()
    func relationChanged(relation: Relation, change: RelationChange)
    func transactionEnded()
}

class WeakRelationObserverProxy: RelationObserver {
    private weak var target: protocol<RelationObserver, AnyObject>?
    private var removal: Void -> Void = { fatalError("Observer method called, but removal function never set.") }
    
    init(target: protocol<RelationObserver, AnyObject>) {
        self.target = target
    }
    
    func register(observee: Relation) {
        removal = observee.addChangeObserver(self)
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
            removal()
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
