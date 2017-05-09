//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import PLRelational

class RelationSignal<T>: SourceSignal<T> {
    fileprivate let relation: Relation
    fileprivate let rowsToValue: (Relation, AnyIterator<Row>) -> T
    fileprivate let isRepeat: (T, T) -> Bool
    internal var latestValue: T?
    private var startedInitialQuery = false
    private var relationObserverRemoval: ObserverRemoval?
    
    init(relation: Relation, initialValue: T?, rowsToValue: @escaping (Relation, AnyIterator<Row>) -> T, isRepeat: @escaping (T, T) -> Bool) {
        self.relation = relation
        self.rowsToValue = rowsToValue
        self.isRepeat = isRepeat
        self.latestValue = initialValue
        
        super.init()
    }

    override func observeImpl(_ observer: Observer) {
        func convertRowsToValue(rows: Set<Row>) -> T {
            return self.rowsToValue(self.relation, AnyIterator(rows.makeIterator()))
        }

        if relationObserverRemoval == nil {
            // This is the first signal observer being registered; begin observing async updates
            // to the underlying relation
            self.relationObserverRemoval = relation.addAsyncObserver(self, postprocessor: convertRowsToValue)
        }

        if let initialValue = latestValue {
            // We already have a value, so deliver it to just the given observer
            // TODO: Should we have a metadata flag to note this as an "initial" value (transient
            // doesn't really tell the whole story)
            observer.notifyValueChanging(initialValue, transient: false)
        } else {
            // We don't already have a value; if we haven't already done so, perform
            // an async query to get the initial value
            observer.notifyBeginPossibleAsyncChange()
            if !startedInitialQuery {
                startedInitialQuery = true
                relation.asyncAllRows(
                    postprocessor: convertRowsToValue,
                    completion: { result in
                        // Note that we can notify all observers, not just the given one
                        if let newValue = result.ok {
                            self.latestValue = newValue
                            self.notifyValueChanging(newValue, transient: false)
                        }
                        self.notifyEndPossibleAsyncChange()
                    }
                )
            }
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
        relationObserverRemoval?()
    }
}

extension RelationSignal: AsyncRelationContentCoalescedObserver {
    func relationWillChange(_ relation: Relation) {
        self.notifyBeginPossibleAsyncChange()
    }

    func relationDidChange(_ relation: Relation, result: Result<T, RelationError>) {
        switch result {
        case .Ok(let newValue):
            if !isRepeat(newValue) {
                self.latestValue = newValue
                self.notifyValueChanging(newValue, transient: false)
            }
            self.notifyEndPossibleAsyncChange()
        case .Err(let err):
            // TODO: actual handling
            fatalError("Got error for relation change: \(err)")
        }
    }
}

extension Relation {
    /// Returns a Signal whose values are derived from this relation.
    public func signal<T>(initialValue: T?, _ rowsToValue: @escaping (Relation, AnyIterator<Row>) -> T) -> Signal<T> {
        return RelationSignal(relation: self, initialValue: initialValue, rowsToValue: rowsToValue, isRepeat: isRepeat)
    }
    
    /// Returns a Signal whose values are derived from this relation.
    public func signal<T: Equatable>(initialValue: T?, _ rowsToValue: @escaping (Relation, AnyIterator<Row>) -> T) -> Signal<T> {
        return RelationSignal(relation: self, initialValue: initialValue, rowsToValue: rowsToValue, isRepeat: isRepeat)
    }
    
    /// Returns a Signal whose values are derived from this relation.
    public func signal<T>(initialValue: T??, _ rowsToValue: @escaping (Relation, AnyIterator<Row>) -> T?) -> Signal<T?> {
        return RelationSignal(relation: self, initialValue: initialValue, rowsToValue: rowsToValue, isRepeat: isRepeat)
    }
    
    /// Returns a Signal whose values are derived from this relation.
    public func signal<T: Equatable>(initialValue: T??, _ rowsToValue: @escaping (Relation, AnyIterator<Row>) -> T?) -> Signal<T?> {
        return RelationSignal(relation: self, initialValue: initialValue, rowsToValue: rowsToValue, isRepeat: isRepeat)
    }
}
