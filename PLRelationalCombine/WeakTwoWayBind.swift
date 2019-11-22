//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

// This file is based largely on the `Assign` implementation from OpenCombine:
//   https://github.com/broadwaylamb/OpenCombine/blob/master/Sources/OpenCombine/Subscribers/Subscribers.Assign.swift

import Combine

fileprivate enum SubscriptionStatus {
    case awaitingSubscription
    case subscribed(Subscription)
    case terminal
}

extension Subscribers {

    public final class WeakTwoWayBind<Root, Input>: Subscriber,
                                                    Cancellable,
                                                    CustomStringConvertible,
                                                    CustomReflectable,
                                                    CustomPlaygroundDisplayConvertible
        where Root: ObservableObject, Root.ObjectWillChangePublisher == ObservableObjectPublisher
    {
        public typealias Failure = Never

        public private(set) weak var object: Root?

        public let keyPath: ReferenceWritableKeyPath<Root, TwoWay<Input>>

        private var status = SubscriptionStatus.awaitingSubscription

        public var description: String { return "WeakTwoWayBind \(Root.self)." }

        public var customMirror: Mirror {
            let children: [Mirror.Child] = [
                ("object", object as Any),
                ("keyPath", keyPath),
                ("status", status as Any)
            ]
            return Mirror(self, children: children)
        }

        public var playgroundDescription: Any { return description }

        public init(object: Root, keyPath: ReferenceWritableKeyPath<Root, TwoWay<Input>>) {
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
                object?[keyPath: keyPath].rawValue = value
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

    /// Assigns output values of this Publisher to a TwoWay property on an object.
    ///
    /// Each output value will be set on the TwoWay via the underlying `rawValue`
    /// property, which means that the TwoWayWriter functions will not be called as
    /// they normally would when setting a value via the TwoWay's `wrappedValue`
    /// property.  This approach prevents feedback loops that might otherwise occur
    /// in two-way binding scenarios.
    ///
    /// NOTE: Unlike `assign(to:)`, this will hold the given object weakly.
    ///
    /// - Parameters:
    ///   - keyPath: The key path of the property to bind.
    ///   - object: The object on which to assign the value.
    /// - Returns: A cancellable instance; used when you end assignment
    ///   of the received value. Deallocation of the result will tear down
    ///   the subscription stream.
    public func bind<Root>(to keyPath: ReferenceWritableKeyPath<Root, TwoWay<Output>>,
                           on object: Root) -> AnyCancellable
        where Root: ObservableObject, Root.ObjectWillChangePublisher == ObservableObjectPublisher
    {
        // Install the given ObservableObject's objectWillChange publisher on the property wrapper
        // so that it can report changes regardless of whether the value is changed internally
        // (by setting rawValue) or via the public setter
        object[keyPath: keyPath].objectWillChange = object.objectWillChange
        
        let subscriber = Subscribers.WeakTwoWayBind(object: object, keyPath: keyPath)
        subscribe(subscriber)
        return AnyCancellable(subscriber)
    }
}
