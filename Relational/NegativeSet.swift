//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//


/// A Set which tracks objects removed from an empty set, conceptually as an object
/// with a count of -1. Removing an object and then adding it results in the set
/// not containing that object. It only supports added and removed, not arbitrary
/// counts.
public struct NegativeSet<T: Hashable> {
    public private(set) var added: Set<T> = []
    public private(set) var removed: Set<T> = []
    
    mutating func unionInPlace(set: Set<T>) {
        let new = set.subtract(removed)
        added.unionInPlace(new)
        removed.subtractInPlace(set)
    }
    
    mutating func subtractInPlace(set: Set<T>) {
        let gone = set.subtract(added)
        removed.unionInPlace(gone)
        added.subtractInPlace(set)
    }
}
