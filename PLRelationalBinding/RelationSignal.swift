//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import PLRelational

class RelationSignal<T>: Signal<T> {
    fileprivate let relation: Relation
    fileprivate let rowsToValue: (Relation, AnyIterator<Row>) -> T
    fileprivate let isRepeat: (T, T) -> Bool
    internal var latestValue: T?
    private var removal: ObserverRemoval?
    
    init(relation: Relation, initialValue: T?, rowsToValue: @escaping (Relation, AnyIterator<Row>) -> T, isRepeat: @escaping (T, T) -> Bool) {
        self.relation = relation
        self.rowsToValue = rowsToValue
        self.isRepeat = isRepeat
        self.latestValue = initialValue
        
        super.init(changeCount: 0, startFunc: { _ in })
    }
    
    override func startImpl(deliverInitial: Bool) {
        func convertRowsToValue(rows: Set<Row>) -> T {
            return self.rowsToValue(self.relation, AnyIterator(rows.makeIterator()))
        }
        
        self.removal = relation.addAsyncObserver(self, postprocessor: convertRowsToValue)

        if deliverInitial {
            self.notifyWillChange()
            if let initialValue = latestValue {
                // Deliver the value that was provided at init time
                self.notifyChanging(initialValue, metadata: ChangeMetadata(transient: false))
                self.notifyDidChange()
            } else {
                // Perform an async query to get the initial value
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
    }

    // The base implemention does not provide an initial value; we override it here and supply an initial
    // value if one was provided at init time.
    override func property() -> AsyncReadableProperty<T> {
        return AsyncReadableProperty(initialValue: self.latestValue, signal: self)
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
