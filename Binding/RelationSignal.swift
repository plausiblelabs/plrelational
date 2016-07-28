//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import libRelational

private class RelationSignal<T>: Signal<T> {
    private let relation: Relation
    private let rowsToValue: (Relation, AnyGenerator<Row>) -> T
    private let isRepeat: (T, T) -> Bool
    private var latestValue: T?
    private var removal: ObserverRemoval!
    
    init(relation: Relation, rowsToValue: (Relation, AnyGenerator<Row>) -> T, isRepeat: (T, T) -> Bool) {
        self.relation = relation
        self.rowsToValue = rowsToValue
        self.isRepeat = isRepeat
        
        super.init(changeCount: 0, startFunc: {})
        
        self.removal = relation.addAsyncObserver(self)
    }
    
    private override func startImpl() {
        self.notifyWillChange()
        relation.asyncAllRows({ result in
            if let rows = result.ok {
                let newValue = self.rowsToValue(self.relation, AnyGenerator(rows.generate()))
                self.latestValue = newValue
                self.notifyChanging(newValue, metadata: ChangeMetadata(transient: false))
            }
            self.notifyDidChange()
        })
    }

    private func isRepeat(newValue: T) -> Bool {
        if let latest = latestValue {
            return isRepeat(newValue, latest)
        } else {
            return false
        }
    }
    
    deinit {
        removal()
    }
}

extension RelationSignal: AsyncRelationContentCoalescedObserver {
    func relationWillChange(relation: Relation) {
        self.notifyWillChange()
    }

    func relationDidChange(relation: Relation, result: Result<Set<Row>, RelationError>) {
        switch result {
        case .Ok(let rows):
            let newValue = self.rowsToValue(self.relation, AnyGenerator(rows.generate()))
            if !isRepeat(newValue) {
                self.latestValue = newValue
                self.notifyChanging(newValue, metadata: ChangeMetadata(transient: false))
            }
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
        return RelationSignal(relation: self, rowsToValue: rowsToValue, isRepeat: isRepeat)
    }
    
    /// Returns a Signal whose values are derived from this relation.
    public func signal<T: Equatable>(rowsToValue: (Relation, AnyGenerator<Row>) -> T) -> Signal<T> {
        return RelationSignal(relation: self, rowsToValue: rowsToValue, isRepeat: isRepeat)
    }
    
    /// Returns a Signal whose values are derived from this relation.
    public func signal<T>(rowsToValue: (Relation, AnyGenerator<Row>) -> T?) -> Signal<T?> {
        return RelationSignal(relation: self, rowsToValue: rowsToValue, isRepeat: isRepeat)
    }
    
    /// Returns a Signal whose values are derived from this relation.
    public func signal<T: Equatable>(rowsToValue: (Relation, AnyGenerator<Row>) -> T?) -> Signal<T?> {
        return RelationSignal(relation: self, rowsToValue: rowsToValue, isRepeat: isRepeat)
    }
}
