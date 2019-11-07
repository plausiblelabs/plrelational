//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

// This file is based largely on the `Assign` implementation from OpenCombine, except changed to
// allow the root to be held weakly.  See original implementation here:
//   https://github.com/broadwaylamb/OpenCombine/blob/master/Sources/OpenCombine/Subscribers/Subscribers.Assign.swift

import Combine

fileprivate enum SubscriptionStatus {
    case awaitingSubscription
    case subscribed(Subscription)
    case terminal
}

extension Subscribers {

    public final class WeakAssign<Root, Input>: Subscriber,
                                                Cancellable,
                                                CustomStringConvertible,
                                                CustomReflectable,
                                                CustomPlaygroundDisplayConvertible
        where Root: AnyObject
    {
        // NOTE: this class has been audited for thread safety.
        // Combine doesn't use any locking here.
        public typealias Failure = Never

        public private(set) weak var object: Root?

        public let keyPath: ReferenceWritableKeyPath<Root, Input>

        private var status = SubscriptionStatus.awaitingSubscription

        public var description: String { return "WeakAssign \(Root.self)." }

        public var customMirror: Mirror {
            let children: [Mirror.Child] = [
                ("object", object as Any),
                ("keyPath", keyPath),
                ("status", status as Any)
            ]
            return Mirror(self, children: children)
        }

        public var playgroundDescription: Any { return description }

        public init(object: Root, keyPath: ReferenceWritableKeyPath<Root, Input>) {
            self.object = object
            self.keyPath = keyPath
        }

        public func receive(subscription: Subscription) {
            switch status {
            case .subscribed, .terminal:
                subscription.cancel()
            case .awaitingSubscription:
                status = .subscribed(subscription)
                subscription.request(.unlimited)
            }
        }

        public func receive(_ value: Input) -> Subscribers.Demand {
            switch status {
            case .subscribed:
                object?[keyPath: keyPath] = value
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
    }
}

extension Publisher where Self.Failure == Never {

    /// Assigns each element from a Publisher to a property on an object.
    /// NOTE: Unlike `assign(to:)`, this will hold the given object weakly.
    ///
    /// - Parameters:
    ///   - keyPath: The key path of the property to assign.
    ///   - object: The object on which to assign the value.
    /// - Returns: A cancellable instance; used when you end assignment
    ///   of the received value. Deallocation of the result will tear down
    ///   the subscription stream.
    public func weakAssign<Root>(to keyPath: ReferenceWritableKeyPath<Root, Output>,
                                 on object: Root) -> AnyCancellable
        where Root: AnyObject
    {
        let subscriber = Subscribers.WeakAssign(object: object, keyPath: keyPath)
        subscribe(subscriber)
        return AnyCancellable(subscriber)
    }
}
