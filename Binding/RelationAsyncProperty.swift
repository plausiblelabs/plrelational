//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import libRelational

extension Relation {
    /// Returns an AsyncReadableProperty that gets its value from this relation.
    public func asyncProperty<V>(relationToValue: Relation -> V) -> AsyncReadableProperty<V> {
        return AsyncReadableProperty(self.signal(relationToValue))
    }
}
