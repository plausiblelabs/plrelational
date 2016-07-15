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
        
        super.init(changeCount: 0)
        
        self.removal = relation.addChangeObserver({ [weak self] _ in
            guard let strongSelf = self else { return }
            // TODO: This is synchronous
            let newValue = rowsToValue(relation, relation.okRows)
            strongSelf.notifyChanging(newValue, metadata: ChangeMetadata(transient: false))
        })
    }
    
    private override func start() {
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

extension Relation {
    /// Returns a Signal whose values are derived from this relation.
    public func signal<T>(rowsToValue: (Relation, AnyGenerator<Row>) -> T) -> Signal<T> {
        return RelationSignal(relation: self, rowsToValue: rowsToValue)
    }
}
