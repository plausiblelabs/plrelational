//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import PLRelational

class RelationSignal<T>: SourceSignal<T> {
    fileprivate let relation: Relation
    fileprivate let rowsToValue: (Relation, AnyIterator<Row>) -> T
    fileprivate let isRepeat: (T, T) -> Bool
    fileprivate var latestValue: T?
    private var relationObserverRemoval: ObserverRemoval?
    private var asyncChangeCount = 0
    private var initialQueryID: UUID?
    
    init(relation: Relation, initialValue: T?, rowsToValue: @escaping (Relation, AnyIterator<Row>) -> T, isRepeat: @escaping (T, T) -> Bool) {
        self.relation = relation
        self.rowsToValue = rowsToValue
        self.isRepeat = isRepeat
        self.latestValue = initialValue
        
        super.init()
    }

    deinit {
        relationObserverRemoval?()
    }

    override func addObserverImpl(_ observer: Observer) {
        func convertRowsToValue(rows: Set<Row>) -> T {
            return self.rowsToValue(self.relation, AnyIterator(rows.makeIterator()))
        }

        if relationObserverRemoval == nil {
            // This is the first signal observer being registered; begin observing async updates
            // to the underlying relation
            self.relationObserverRemoval = relation.addAsyncObserver(self, postprocessor: convertRowsToValue)
        }

        // First deliver one or more BeginPossibleAsync events if we happen to be in the middle of a possible
        // async change
        for _ in 0..<asyncChangeCount {
            observer.notifyBeginPossibleAsyncChange()
        }

        if let initialValue = latestValue {
            // We already have a value, so deliver it to just the given observer
            // TODO: Should we have a metadata flag to note this as an "initial" value (transient
            // doesn't really tell the whole story)
            observer.notifyValueChanging(initialValue, transient: false)
        } else {
            // We don't already have a value; if we haven't already done so, perform
            // an async query to get the initial value
            if initialQueryID == nil {
                let currentInitialQueryID = UUID()
                initialQueryID = currentInitialQueryID
                
                self.beginPossibleAsyncChange()
                
                relation.asyncAllRows(
                    postprocessor: convertRowsToValue,
                    completion: { [weak self] result in
                        guard let strongSelf = self else { return }
                        
                        // Ignore completion if all observers were removed and we initiated another
                        // query before this one had a chance to complete
                        guard strongSelf.initialQueryID == currentInitialQueryID else { return }
                        
                        // Note that we notify all observers, not just the given one, since more
                        // observers may have been added since we started the initial query
                        if let newValue = result.ok {
                            strongSelf.latestValue = newValue
                            strongSelf.notifyValueChanging(newValue, transient: false)
                        }
                        strongSelf.endPossibleAsyncChange()
                    }
                )
            }
        }
    }
    
    override func onEmptyObserverSet() {
        // When no one is left observing this signal, stop observing the underlying relation
        // TODO: Should we also nil out latestValue so that it has to be refetched when someone
        // starts observing again?
        relationObserverRemoval?()
        relationObserverRemoval = nil
        asyncChangeCount = 0
        initialQueryID = nil
    }

    fileprivate func isRepeat(_ newValue: T) -> Bool {
        if let latest = latestValue {
            return isRepeat(newValue, latest)
        } else {
            return false
        }
    }
    
    fileprivate func beginPossibleAsyncChange() {
        asyncChangeCount += 1
        self.notifyBeginPossibleAsyncChange()
    }

    fileprivate func endPossibleAsyncChange() {
        asyncChangeCount -= 1
        self.notifyEndPossibleAsyncChange()
    }
}

extension RelationSignal: AsyncRelationContentCoalescedObserver {
    func relationWillChange(_ relation: Relation) {
        self.beginPossibleAsyncChange()
    }

    func relationDidChange(_ relation: Relation, result: Result<T, RelationError>) {
        switch result {
        case .Ok(let newValue):
            if !isRepeat(newValue) {
                self.latestValue = newValue
                self.notifyValueChanging(newValue, transient: false)
            }
            self.endPossibleAsyncChange()
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
