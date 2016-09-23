//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import libRelational

private class RelationSignal<T>: Signal<T> {
    fileprivate let relation: Relation
    fileprivate let rowsToValue: (Relation, AnyIterator<Row>) -> T
    fileprivate let isRepeat: (T, T) -> Bool
    fileprivate var latestValue: T?
    private var removal: ObserverRemoval?
    
    init(relation: Relation, rowsToValue: @escaping (Relation, AnyIterator<Row>) -> T, isRepeat: @escaping (T, T) -> Bool) {
        self.relation = relation
        self.rowsToValue = rowsToValue
        self.isRepeat = isRepeat
        
        super.init(changeCount: 0, startFunc: { _ in })
    }
    
    private override func startImpl(deliverInitial: Bool) {
        func convertRowsToValue(rows: Set<Row>) -> T {
            return self.rowsToValue(self.relation, AnyIterator(rows.makeIterator()))
        }
        
        self.removal = relation.addAsyncObserver(self, postprocessor: convertRowsToValue)
        
        if deliverInitial {
            self.notifyWillChange()
            relation.asyncAllRows(
                postprocessor: convertRowsToValue,
                completion: { result in
                    if let newValue = result.ok {
                        self.latestValue = newValue
                        self.notifyChanging(newValue, metadata: ChangeMetadata(transient: false))
                    }
                    self.notifyDidChange()
                }
            )
        }
    }

    fileprivate func isRepeat(_ newValue: T) -> Bool {
        if let latest = latestValue {
            return isRepeat(newValue, latest)
        } else {
            return false
        }
    }
    
    deinit {
        removal?()
    }
}

extension RelationSignal: AsyncRelationContentCoalescedObserver {
    func relationWillChange(_ relation: Relation) {
        self.notifyWillChange()
    }

    func relationDidChange(_ relation: Relation, result: Result<T, RelationError>) {
        switch result {
        case .Ok(let newValue):
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
    public func signal<T>(_ rowsToValue: @escaping (Relation, AnyIterator<Row>) -> T) -> Signal<T> {
        return RelationSignal(relation: self, rowsToValue: rowsToValue, isRepeat: isRepeat)
    }
    
    /// Returns a Signal whose values are derived from this relation.
    public func signal<T: Equatable>(_ rowsToValue: @escaping (Relation, AnyIterator<Row>) -> T) -> Signal<T> {
        return RelationSignal(relation: self, rowsToValue: rowsToValue, isRepeat: isRepeat)
    }
    
    /// Returns a Signal whose values are derived from this relation.
    public func signal<T>(_ rowsToValue: @escaping (Relation, AnyIterator<Row>) -> T?) -> Signal<T?> {
        return RelationSignal(relation: self, rowsToValue: rowsToValue, isRepeat: isRepeat)
    }
    
    /// Returns a Signal whose values are derived from this relation.
    public func signal<T: Equatable>(_ rowsToValue: @escaping (Relation, AnyIterator<Row>) -> T?) -> Signal<T?> {
        return RelationSignal(relation: self, rowsToValue: rowsToValue, isRepeat: isRepeat)
    }
}
