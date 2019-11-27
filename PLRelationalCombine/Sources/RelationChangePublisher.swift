//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Combine
import PLRelational

public class RelationChangePublisher<Element>: Publisher {
    
    public typealias Output = RelationChangeSummary<Element>
    public typealias Failure = RelationError

    private let relation: Relation
    private let idAttr: Attribute
    private let mapFunc: (Row) -> Element

    init(relation: Relation, idAttr: Attribute, mapFunc: @escaping (Row) -> Element) {
        self.relation = relation
        self.idAttr = idAttr
        self.mapFunc = mapFunc
    }

    public func receive<S>(subscriber: S) where S : Subscriber, S.Input == RelationChangeSummary<Element>, S.Failure == RelationError {
        // TODO: For now, each subscription makes an initial query and maintains its own relation observer.
        // Ideally we would share state between subscriptions to avoid redundant work.
        subscriber.receive(subscription: InnerSubscription(relation: relation, idAttr: idAttr, mapFunc: mapFunc, downstream: subscriber))
    }
}

extension RelationChangePublisher {

    final class InnerSubscription<Downstream: Subscriber>
        : Subscription, AsyncRelationChangeCoalescedObserver
    where Downstream.Input == Output, Downstream.Failure == Failure
    {
        private let relation: Relation
        private let idAttr: Attribute
        private let mapFunc: (Row) -> Element

        private var downstream: Downstream?
        private var relationObserverRemoval: ObserverRemoval?

        init(relation: Relation, idAttr: Attribute, mapFunc: @escaping (Row) -> Element, downstream: Downstream) {
            self.relation = relation
            self.idAttr = idAttr
            self.mapFunc = mapFunc
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
            self.relationObserverRemoval = relation.addAsyncObserver(self)

            // Perform an async query to get the initial array
            relation.asyncAllRows{ [weak self] result in
                guard let strongSelf = self else { return }

                switch result {
                case .Ok(let rows):
                    // TODO: Perhaps we should use an enum to differentiate initial set vs subsequent changes?
                    let summary = RelationChangeSummary(added: Array(rows.map(strongSelf.mapFunc)), updated: [], deleted: [])
                    _ = strongSelf.downstream?.receive(summary)
                case .Err(let error):
                    if let downstream = strongSelf.downstream {
                        downstream.receive(completion: .failure(error))
                    }
                    // Cancel after receiving any relation error
                    strongSelf.cancel()
                }
            }
        }

        func cancel() {
            relationObserverRemoval?()
            relationObserverRemoval = nil
            downstream = nil
        }

        func relationWillChange(_ relation: Relation) {
        }

        func relationDidChange(_ relation: Relation, result: Result<RowChange, RelationError>) {
            switch result {
            case .Ok(let change):
                // Compute changes
                let summary = change.summary(idAttr: idAttr, self.mapFunc)
                if !summary.isEmpty {
                    _ = self.downstream?.receive(summary)
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

extension Relation {

    /// Returns a Publisher, sourced from this relation, that delivers a RelationChangeSummary for each
    /// set of changes that are made to the relation.
    public func changes<Element>(id: Attribute = "id", _ mapFunc: @escaping (Row) -> Element) -> RelationChangePublisher<Element> {
        return RelationChangePublisher(relation: self, idAttr: id, mapFunc: mapFunc)
    }
}
