//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

// This file is loosely based on the `Assign` implementation from OpenCombine:
//   https://github.com/broadwaylamb/OpenCombine/blob/master/Sources/OpenCombine/Subscribers/Subscribers.Assign.swift

import Combine
import PLRelational

fileprivate enum SubscriptionStatus {
    case awaitingSubscription
    case subscribed(Subscription)
    case terminal
}

private final class RelationArrayReduce<Root, Value, OrderBy>
    : Subscriber,
      Cancellable,
      CustomStringConvertible,
      CustomReflectable,
      CustomPlaygroundDisplayConvertible
    where Root: AnyObject, OrderBy: Comparable, Value: Identifiable, Value.ID == RelationValue
{
    public typealias Input = RelationChangeSummary
    public typealias Failure = Never

    // TODO: This is held weakly to match WeakAssign; need to think more about the right approach here
    private weak var object: Root?
    private let keyPath: ReferenceWritableKeyPath<Root, [Value]>
    
    private let idAttr: Attribute
    private let orderKeyPath: KeyPath<Value, OrderBy>
    private let orderFunc: (OrderBy, OrderBy) -> Bool
    private let mapFunc: (Row) -> Value

    private var status = SubscriptionStatus.awaitingSubscription

    public var description: String { return "RelationArrayReduce \(Root.self)." }

    public var customMirror: Mirror {
        let children: [Mirror.Child] = [
            ("object", object as Any),
            ("keyPath", keyPath),
            ("idAttr", idAttr),
            ("orderKeyPath", orderKeyPath),
            ("status", status as Any)
        ]
        return Mirror(self, children: children)
    }

    public var playgroundDescription: Any { return description }

    public init(object: Root, keyPath: ReferenceWritableKeyPath<Root, [Value]>,
                idAttr: Attribute, orderKeyPath: KeyPath<Value, OrderBy>, descending: Bool,
                mapFunc: @escaping (Row) -> Value)
    {
        self.object = object
        self.keyPath = keyPath
        self.idAttr = idAttr
        self.orderKeyPath = orderKeyPath
        if descending {
            self.orderFunc = { $0 > $1 }
        } else {
            self.orderFunc = { $0 < $1 }
        }
        self.mapFunc = mapFunc
    }

    public func receive(subscription: Subscription) {
        switch status {
        case .subscribed, .terminal:
            subscription.cancel()
        case .awaitingSubscription:
            // TODO: Check target array here and fail if it is non-empty (since our logic assumes we're
            // starting with a fresh array)
            status = .subscribed(subscription)
            subscription.request(.unlimited)
        }
    }

    public func receive(_ value: RelationChangeSummary) -> Subscribers.Demand {
        switch status {
        case .subscribed:
            if var array = object?[keyPath: keyPath] {
                if !value.isEmpty {
                    delete(value.deleted, from: &array)
                    insert(value.added, into: &array)
                    update(value.updated, in: &array)
                }
                object?[keyPath: keyPath] = array
            }
        case .awaitingSubscription, .terminal:
            break
        }
        return .none
    }

    public func receive(completion: Subscribers.Completion<Never>) {
        cancel()
    }

    public func cancel() {
        guard case let .subscribed(subscription) = status else {
            return
        }
        subscription.cancel()
        status = .terminal
        object = nil
    }
    
    private func insert(_ rows: [Row], into array: inout [Value]) {
        for row in rows {
            let elem = mapFunc(row)
            _ = array.insertSorted(elem, by: orderKeyPath, orderFunc)
        }
    }

    private func delete(_ rows: [Row], from array: inout [Value]) {
        for row in rows {
            let rowId = row[idAttr]
            if let index = array.firstIndex(where: { $0.id == rowId }) {
                array.remove(at: index)
            }
        }
    }

    private func update(_ rows: [Row], in array: inout [Value]) {
        for row in rows {
            let rowId = row[idAttr]
            guard let index = array.firstIndex(where: { $0.id == rowId }) else {
                // TODO: Treat this as an error?
                continue
            }
            
            // TODO: For now, always delete the existing item and insert a new one;
            // this needs to be fixed to:
            //   - allow for extracting the order attribute from the row without requiring caller to make a new element
            //   - pass the existing item to mapFunc so that the caller can decide whether to make a new one
            //   - use `move` in the case where it is a pure move
            //   - otherwise update the element in place
            array.remove(at: index)
            let elem = mapFunc(row)
            _ = array.insertSorted(elem, by: orderKeyPath, orderFunc)
        }
    }
}

// TODO: Preserve RelationErrors (i.e., don't force Never here)
extension Publisher where Self.Output == RelationChangeSummary, Self.Failure == Never {

    /// TODO: Docs
    public func reduce<Root, Value, OrderBy>(to keyPath: ReferenceWritableKeyPath<Root, [Value]>,
                                             on object: Root,
                                             id idAttr: Attribute = "id",
                                             sortedBy orderKeyPath: KeyPath<Value, OrderBy>, descending: Bool = false,
                                             _ mapFunc: @escaping (Row) -> Value) -> AnyCancellable
        // TODO: Relax the Value.ID == RelationValue restriction
        where Root: AnyObject, OrderBy: Comparable, Value: Identifiable, Value.ID == RelationValue
    {
        let subscriber = RelationArrayReduce(object: object, keyPath: keyPath,
                                             idAttr: idAttr,
                                             orderKeyPath: orderKeyPath, descending: descending,
                                             mapFunc: mapFunc)
        subscribe(subscriber)
        return AnyCancellable(subscriber)
    }
}
