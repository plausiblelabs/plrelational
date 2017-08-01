//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

/// :nodoc:
extension Set {
    /// As of Xcode 8.3/Swift 3.1, the implementation of Set's `subtract` is kind of dumb:
    ///
    ///    for item in other {
    ///        remove(item)
    ///    }
    ///
    /// That means that subtracting a large set from a small set is unnecessarily slow.
    /// This reimplements subtraction doing the same thing, but iterating over the smaller
    /// of the two sets.
    public mutating func fastSubtract(_ other: Set<Element>) {
        if other.count > self.count {
            self = Set(self.lazy.filter({ !other.contains($0) }))
        } else {
            for item in other {
                self.remove(item)
            }
        }
    }
    
    /// A non-mutating wrapper around fastSubtract. Just creates a mutable copy and mutates it
    /// using fastSubtract.
    public func fastSubtracting(_ other: Set<Element>) -> Set<Element> {
        var result = self
        result.fastSubtract(other)
        return result
    }
}
