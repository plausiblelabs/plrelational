//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

/// :nodoc: Implementation detail (will be made non-public eventually)
public extension Dictionary {
    public init<S: Sequence>(_ seq: S) where S.Iterator.Element == (Key, Value) {
        self.init()
        for (k, v) in seq {
            self[k] = v
        }
    }
}
