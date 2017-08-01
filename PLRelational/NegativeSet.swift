//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

/// :nodoc:
/// A Set which tracks objects removed from an empty set, conceptually as an object
/// with a count of -1. Removing an object and then adding it results in the set
/// not containing that object. It only supports added and removed, not arbitrary
/// counts.
public struct NegativeSet<T: Hashable> {
    /// The values which have been added to the set.
    public fileprivate(set) var added: Set<T> = []
    
    /// The values which have been removed from the set.
    public fileprivate(set) var removed: Set<T> = []
    
    /// Create a new set.
    public init() {}
    
    /// Add all elements in `set` to this set.
    public mutating func unionInPlace(_ set: Set<T>) {
        let new = set.fastSubtracting(removed)
        added.formUnion(new)
        removed.fastSubtract(set)
    }
    
    /// Remove all elements in `set` from this set.
    public mutating func subtractInPlace(_ set: Set<T>) {
        let gone = set.fastSubtracting(added)
        removed.formUnion(gone)
        added.fastSubtract(set)
    }
    
    /// Clear this set by resetting `added` and `removed` to empty sets.
    public mutating func removeAll() {
        added.removeAll()
        removed.removeAll()
    }
}
