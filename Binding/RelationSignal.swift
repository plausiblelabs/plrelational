//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import libRelational

private class RelationSignal<T>: Signal<T> {
    private let relation: Relation
    private let rowsToValue: (Relation, AnyGenerator<Row>) -> T
    private var removal: ObserverRemoval!
    
    init(relation: Relation, rowsToValue: (Relation, AnyGenerator<Row>) -> T) {
        self.relation = relation
        self.rowsToValue = rowsToValue
        
        super.init(changeCount: 0, startFunc: {})
        
        self.removal = relation.addAsyncObserver(self)
    }
    
    private override func startImpl() {
        self.notifyWillChange()
        relation.asyncAllRows({ result in
            if let rows = result.ok {
                let newValue = self.rowsToValue(self.relation, AnyGenerator(rows.generate()))
                self.notifyChanging(newValue, metadata: ChangeMetadata(transient: false))
            }
            self.notifyDidChange()
        })
    }
    
    deinit {
        removal()
    }
}

extension RelationSignal: AsyncRelationChangeCoalescedObserver {
    func relationWillChange(relation: Relation) {
        self.notifyWillChange()
    }
    
    func relationDidChange(relation: Relation, result: Result<NegativeSet<Row>, RelationError>) {
        switch result {
        case .Ok(let change):
            // TODO: Need to look at both added and removed (and compute updates)
            let newValue = self.rowsToValue(self.relation, AnyGenerator(change.added.generate()))
            self.notifyChanging(newValue, metadata: ChangeMetadata(transient: false))
            self.notifyDidChange()
        case .Err(let err):
            // TODO: actual handling
            fatalError("Got error for relation change: \(err)")
        }
    }
}

extension Relation {
    /// Returns a Signal whose values are derived from this relation.
    public func signal<T>(rowsToValue: (Relation, AnyGenerator<Row>) -> T) -> Signal<T> {
        return RelationSignal(relation: self, rowsToValue: rowsToValue)
    }
}
