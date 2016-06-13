//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

public extension Dictionary {
    public init<S: SequenceType where S.Generator.Element == (Key, Value)>(_ seq: S) {
        self.init()
        for (k, v) in seq {
            self[k] = v
        }
    }
}
