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

/// Each element of the destination array for a `RelationArrayReduce` operation must
/// implement this protocol.  The wrapped `Element` type should be lightweight (i.e., cheap
/// to instantiate), while the `ElementViewModel` is class-bound and is expected to be
/// reused when possible.
public protocol ElementViewModel: AnyObject {
    associatedtype Element: Identifiable
    var element: Element { get }
}

private final class RelationArrayReduce<Root, Target>
    : Subscriber,
      Cancellable,
      CustomStringConvertible,
      CustomReflectable,
      CustomPlaygroundDisplayConvertible
    where Root: AnyObject, Target: ElementViewModel
{
    public typealias Input = RelationChangeSummary<Target.Element>
    public typealias Failure = Never

    // TODO: This is held weakly to match WeakBind; need to think more about the right approach here
    private weak var object: Root?
    private let keyPath: ReferenceWritableKeyPath<Root, [Target]>
    
    private let mapFunc: (_ existing: Target?, _ element: Target.Element) -> Target?
    private let orderFunc: (Target.Element, Target.Element) -> Bool

    private var status = SubscriptionStatus.awaitingSubscription

    public var description: String { return "RelationArrayReduce \(Root.self)." }

    public var customMirror: Mirror {
        let children: [Mirror.Child] = [
            ("object", object as Any),
            ("keyPath", keyPath),
            ("status", status as Any)
        ]
        return Mirror(self, children: children)
    }

    public var playgroundDescription: Any { return description }

    public init(object: Root, keyPath: ReferenceWritableKeyPath<Root, [Target]>,
                mapFunc: @escaping (_ existing: Target?, _ element: Target.Element) -> Target?,
                orderFunc: @escaping (Target.Element, Target.Element) -> Bool)
    {
        self.object = object
        self.keyPath = keyPath
        self.mapFunc = mapFunc
        self.orderFunc = orderFunc
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

    public func receive(_ value: RelationChangeSummary<Target.Element>) -> Subscribers.Demand {
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
    
    private func insert(_ elements: [Target.Element], into array: inout [Target]) {
        for elem in elements {
            if let target = mapFunc(nil, elem) {
                _ = array.insertSorted(target, by: \.element, orderFunc)
            }
        }
    }

    private func delete(_ elements: [Target.Element], from array: inout [Target]) {
        for elem in elements {
            let elemId = elem.id
            if let index = array.firstIndex(where: { $0.element.id == elemId }) {
                array.remove(at: index)
            }
        }
    }

    private func update(_ elements: [Target.Element], in array: inout [Target]) {
        for elem in elements {
            let elemId = elem.id
            guard let index = array.firstIndex(where: { $0.element.id == elemId }) else {
                // TODO: Treat this as an error?
                continue
            }

            // Get the existing target item
            let existingTarget = array[index]

            // Pass it to the map function along with the updated element data
            let updatedTarget: Target
            if let newTarget = mapFunc(existingTarget, elem) {
                // The callee created a new target item
                array[index] = newTarget
                updatedTarget = newTarget
            } else {
                // The callee wants to use the existing target item
                updatedTarget = existingTarget
            }

            // See if the order is changing.  Note that we could just always remove+insert,
            // but the following approach is slightly more efficient in that it only moves
            // elements if the order is actually changing, and otherwise keeps things in place.
            let orderChanging = !array.isElementOrdered(at: index, by: \.element, orderFunc)
            if orderChanging {
                // TODO: Would there be any benefit to using SwiftUI's `move` extension here?
                array.remove(at: index)
                _ = array.insertSorted(updatedTarget, by: \.element, orderFunc)
            }
        }
    }
}

extension Publisher where Self.Failure == Never {

    /// TODO: Docs
    public func reduce<Root, Target>(to keyPath: ReferenceWritableKeyPath<Root, [Target]>,
                                      on object: Root,
                                      orderBy orderFunc: @escaping (Target.Element, Target.Element) -> Bool,
                                      _ mapFunc: @escaping (_ existing: Target?, _ element: Target.Element) -> Target?) -> AnyCancellable
        where Root: AnyObject, Target: ElementViewModel, Self.Output == RelationChangeSummary<Target.Element>
    {
        let subscriber = RelationArrayReduce(object: object, keyPath: keyPath, mapFunc: mapFunc, orderFunc: orderFunc)
        subscribe(subscriber)
        return AnyCancellable(subscriber)
    }
}
