//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

// This file is loosely based on the `ReplaceError` implementation from OpenCombine:
//   https://github.com/broadwaylamb/OpenCombine/blob/master/Sources/OpenCombine/Publishers/Publishers.ReplaceError.swift

import Combine

extension Publisher {
    /// Swallows any errors in the stream and logs them to the console.
    /// This is only intended to be used for rough development and isn't likely to be
    /// useful in production.
    public func logError() -> LogError<Self> {
        return .init(upstream: self)
    }
}

/// A publisher that swallows any errors in the stream and logs them to the console.
/// This is only intended to be used for rough development and isn't likely to be
/// useful in production.
public struct LogError<Upstream: Publisher>: Publisher {

    public typealias Output = Upstream.Output
    public typealias Failure = Never

    public let upstream: Upstream

    public init(upstream: Upstream) {
        self.upstream = upstream
    }

    public func receive<Downstream: Subscriber>(subscriber: Downstream)
        where Upstream.Output == Downstream.Input, Downstream.Failure == Never
    {
        upstream.subscribe(Inner(downstream: subscriber))
    }
}

extension LogError {

    private struct Inner<Downstream: Subscriber>
        : Subscriber,
          CustomStringConvertible,
          CustomReflectable,
          CustomPlaygroundDisplayConvertible
        where Upstream.Output == Downstream.Input, Downstream.Failure == Never
    {
        typealias Input = Upstream.Output
        typealias Failure = Upstream.Failure

        private let downstream: Downstream

        let combineIdentifier = CombineIdentifier()

        var description: String { return "LogError" }

        var customMirror: Mirror { return Mirror(self, children: EmptyCollection()) }

        var playgroundDescription: Any { return description }

        init(downstream: Downstream) {
            self.downstream = downstream
        }

        func receive(subscription: Subscription) {
            downstream.receive(subscription: subscription)
        }

        func receive(_ input: Input) -> Subscribers.Demand {
            return downstream.receive(input)
        }

        func receive(completion: Subscribers.Completion<Failure>) {
            switch completion {
            case .finished:
                downstream.receive(completion: .finished)
            case .failure(let error):
                Swift.print("Downstream publisher produced an error: \(error)")
            }
        }
    }
}
