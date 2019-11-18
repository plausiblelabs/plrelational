//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Combine

/// Alias for a set of cancellables, with a `cancel` convenience method that
/// allows for one-shot cancellation.
public typealias CancellableBag = Set<AnyCancellable>

extension Set where Element: Cancellable {
    /// Cancel each cancellable in this set.
    public func cancel() {
        self.forEach{ $0.cancel() }
    }
}
