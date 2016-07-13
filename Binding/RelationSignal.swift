//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import libRelational

private class RelationSignal<T>: Signal<T> {
    private var removal: ObserverRemoval!
    
    init(relation: Relation, relationToValue: Relation -> T) {
        super.init()
        self.removal = relation.addChangeObserver({ [weak self] _ in
            guard let strongSelf = self else { return }
            let newValue = relationToValue(relation)
            strongSelf.notifyChanging(newValue, metadata: ChangeMetadata(transient: false))
        })
    }
    
    deinit {
        removal()
    }
}

extension Relation {
    /// Returns a Signal whose values are derived from this relation.
    public func signal<T>(relationToValue: Relation -> T) -> Signal<T> {
        return RelationSignal(relation: self, relationToValue: relationToValue)
    }
}
