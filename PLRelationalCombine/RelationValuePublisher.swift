//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Combine
import PLRelational

typealias ObserverRemoval = () -> Void

public class RelationValuePublisher<T>: Publisher {
    public typealias Output = T
    public typealias Failure = RelationError
    
    public let relation: Relation
    public let ignoreInitiator: InitiatorTag?
    public let rowsToValue: (Relation, Set<Row>) -> T
    
    init(relation: Relation, ignoreInitiator: InitiatorTag? = nil, rowsToValue: @escaping (Relation, Set<Row>) -> T) {
        self.relation = relation
        self.ignoreInitiator = ignoreInitiator
        self.rowsToValue = rowsToValue
    }

    public func receive<S>(subscriber: S) where S : Subscriber, S.Input == T, S.Failure == RelationError {
        // TODO: For now, each subscription makes an initial query and maintains its own relation observer.
        // Ideally we would share state between subscriptions to avoid redundant work.
        subscriber.receive(subscription: InnerSubscription(relation: relation,
                                                           rowsToValue: rowsToValue, ignoreInitiator: ignoreInitiator,
                                                           downstream: subscriber))
    }
}

extension RelationValuePublisher {

    final class InnerSubscription<Downstream: Subscriber>
        : Subscription, AsyncRelationContentCoalescedObserver
    where Downstream.Input == Output, Downstream.Failure == Failure
    {
        private let relation: Relation
        private let rowsToValue: (Relation, Set<Row>) -> T
        private let ignoreInitiator: InitiatorTag?
        
        private var downstream: Downstream?
        private var relationObserverRemoval: ObserverRemoval?
        
        init(relation: Relation,
             rowsToValue: @escaping (Relation, Set<Row>) -> T,
             ignoreInitiator: InitiatorTag?,
             downstream: Downstream)
        {
            self.relation = relation
            self.rowsToValue = rowsToValue
            self.ignoreInitiator = ignoreInitiator
            self.downstream = downstream
        }

        deinit {
            relationObserverRemoval?()
        }

        func request(_ demand: Subscribers.Demand) {
            // TODO: Honor `demand.max`?

            // Ignore any requests if it has already been cancelled
            if self.downstream == nil {
                return
            }
            
            // TODO: For now, we only handle one request and ignore the others
            if self.relationObserverRemoval != nil {
                fatalError("Only one request is supported for now")
            }
            
            // Begin observing async updates to the underlying relation
            func convertRowsToValue(rows: Set<Row>) -> T {
                return self.rowsToValue(self.relation, rows)
            }
            self.relationObserverRemoval = relation.addAsyncObserver(self, postprocessor: convertRowsToValue)

            // Perform an async query to get the initial value
            relation.asyncAllRows(
                postprocessor: convertRowsToValue,
                completion: { [weak self] result in
                    guard let strongSelf = self else { return }

                    switch result {
                    case .Ok(let value):
                        _ = strongSelf.downstream?.receive(value)
                    case .Err(let error):
                        if let downstream = strongSelf.downstream {
                            downstream.receive(completion: .failure(error))
                        }
                        // Cancel after receiving any relation error
                        strongSelf.cancel()
                    }
                }
            )
        }
        
        func cancel() {
            relationObserverRemoval?()
            relationObserverRemoval = nil
            downstream = nil
        }

        func relationWillChange(_ relation: Relation) {
        }

        func relationDidChange(_ relation: Relation, result: Result<T, RelationError>, initiators: InitiatorTagSet) {
            switch result {
            case .Ok(let value):
                let deliverValue: Bool
                if let initiator = ignoreInitiator {
                    // Don't deliver the value if the change was initiated by (just) the given initiator
                    deliverValue = initiators.count != 1 || initiators.first! != initiator
                } else {
                    // No ignored initiator, so always deliver the value
                    deliverValue = true
                }
                if deliverValue {
                    _ = self.downstream?.receive(value)
                }
                
            case .Err(let error):
                if let downstream = self.downstream {
                    downstream.receive(completion: .failure(error))
                }
                
                // Cancel after receiving any relation error
                self.cancel()
            }
        }
    }
}

// TODO: Find a home for this
public class RowArrayElement: Identifiable {
    public let id: RelationValue
    public let row: Row

    init(id: RelationValue, row: Row) {
        self.id = id
        self.row = row
    }
}

extension RelationValuePublisher {

    /// Returns a Publisher that skips any changes for which there is exactly one initiator tag that matches the given tag.
    /// This can be used in bidirectional binding scenarios to ignore "self-initiated" changes.
    public func ignoreInitiator(_ initiator: InitiatorTag) -> RelationValuePublisher<T> {
        return RelationValuePublisher(relation: self.relation, ignoreInitiator: initiator, rowsToValue: self.rowsToValue)
    }
}

extension Relation {
    
    // MARK: - Publishers

    /// Returns a Publisher that delivers the content of this relation as a set of rows.
    public func allRows() -> RelationValuePublisher<Set<Row>> {
        return RelationValuePublisher(relation: self, rowsToValue: {
            $1
        })
    }

    /// Returns a Publisher that delivers true when the set of rows is non-empty, false otherwise.
    public func nonEmpty() -> RelationValuePublisher<Bool> {
        return RelationValuePublisher(relation: self, rowsToValue: {
            !$1.isEmpty
        })
    }

    /// Returns a Publisher, sourced from this relation, that delivers a single string value if there is exactly
    /// one row, otherwise delivers an empty string.
    public func oneString() -> RelationValuePublisher<String> {
        return RelationValuePublisher(relation: self, rowsToValue: {
            $0.extractOneString(from: AnyIterator($1.makeIterator()))
        })
    }
    
    /// Returns a Publisher, sourced from this relation, that delivers a single string value if there is exactly
    /// one row, otherwise delivers nil.
    public func oneStringOrNil() -> RelationValuePublisher<String?> {
        return RelationValuePublisher(relation: self, rowsToValue: {
            $0.extractOneStringOrNil(from: AnyIterator($1.makeIterator()))
        })
    }

    /// Returns a Publisher, sourced from this relation, that delivers a set of all strings for the
    /// single attribute.
    public func allStrings() -> RelationValuePublisher<Set<String>> {
        return RelationValuePublisher(relation: self, rowsToValue: {
            $0.extractAllValuesForSingleAttribute(from: AnyIterator($1.makeIterator()), { $0.get() as String? })
        })
    }

    // TODO: Add comments mentioning that this is a less efficient version of RelationArrayPublisher, since it refetches
    // the entire data set any time there is a change in the underlying relation (so it's only useful for small data sets
    // and/or quick bootstrapping)
    public func sortedRows(idAttr: Attribute, orderAttr: Attribute, descending: Bool = false) -> RelationValuePublisher<[RowArrayElement]> {
        precondition(self.scheme.attributes.isSuperset(of: [idAttr, orderAttr]))

        return RelationValuePublisher(relation: self, rowsToValue: {
            $0.extractAllRowsAsArray(from: AnyIterator($1.makeIterator()), idAttr: idAttr, orderAttr: orderAttr, descending: descending)
        })
    }
}

extension Relation {
    
    // MARK: - Extract all rows

    /// TODO: Docs
    public func extractAllRowsAsArray(from rows: AnyIterator<Row>, idAttr: Attribute, orderAttr: Attribute, descending: Bool) -> [RowArrayElement] {
        let orderFunc: (RelationValue, RelationValue) -> Bool
        if descending {
            orderFunc = { $0 > $1 }
        } else {
            orderFunc = { $0 < $1 }
        }

        return rows
            .sorted{ orderFunc($0[orderAttr], $1[orderAttr]) }
            .map{ RowArrayElement(id: $0[idAttr], row: $0) }
    }

    // MARK: Extract all values

    /// Returns a set of all values for the single attribute, built from one transformed value for each non-error row
    /// in the given set.
    public func extractAllValuesForSingleAttribute<V: Hashable>(from rows: AnyIterator<Row>, _ transform: @escaping (RelationValue) -> V?) -> Set<V> {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        return Set(rows
            .compactMap{transform($0[attr])})
    }

    // MARK: - Extract one row

    /// Returns a single row if there is exactly one row in the given set, otherwise returns nil.
    public func extractOneRow(_ rows: AnyIterator<Row>) -> Row? {
        if let row = rows.next() {
            if rows.next() == nil {
                return row
            } else {
                return nil
            }
        } else {
            return nil
        }
    }

    // MARK: - Extract one value

    /// Returns a single transformed value if there is exactly one row in the given set, otherwise returns nil.
    public func extractValueFromOneRow<V>(_ rows: AnyIterator<Row>, _ transform: @escaping (Row) -> V?) -> V? {
        return extractOneRow(rows).flatMap{ transform($0) }
    }

    /// Returns a single transformed value if there is exactly one row in the given set, otherwise returns nil.
    public func extractValueFromOneRow<V>(_ rows: AnyIterator<Row>, _ transform: @escaping (Row) -> V?, orDefault defaultValue: V) -> V {
        return extractValueFromOneRow(rows, transform) ?? defaultValue
    }

    /// Returns a single transformed value if there is exactly one row in the given set, otherwise returns nil.
    public func extractOneValueOrNil<V>(from rows: AnyIterator<Row>, _ transform: @escaping (RelationValue) -> V?) -> V? {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        return extractValueFromOneRow(rows, { transform($0[attr]) })
    }

    /// Returns a single transformed value if there is exactly one row in the given set, otherwise returns the
    /// given default value.
    public func extractOneValue<V>(from rows: AnyIterator<Row>, _ transform: @escaping (RelationValue) -> V?, orDefault defaultValue: V) -> V {
        return extractOneValueOrNil(from: rows, transform) ?? defaultValue
    }

    /// Returns a single RelationValue if there is exactly one row in the given set, otherwise returns nil.
    public func extractOneRelationValueOrNil(from rows: AnyIterator<Row>) -> RelationValue? {
        return extractOneValueOrNil(from: rows, { $0 })
    }

    // MARK: - Extract one String

    /// Returns a a single string value if there is exactly one row in the given set, otherwise returns nil.
    public func extractOneStringOrNil(from rows: AnyIterator<Row>) -> String? {
        return extractOneValueOrNil(from: rows, { $0.get() })
    }

    /// Returns a single string value if there is exactly one row in the given set, otherwise returns
    /// an empty string.
    public func extractOneString(from rows: AnyIterator<Row>) -> String {
        return extractOneStringOrNil(from: rows) ?? ""
    }
}
