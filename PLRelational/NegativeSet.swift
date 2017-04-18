//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//


/// A Set which tracks objects removed from an empty set, conceptually as an object
/// with a count of -1. Removing an object and then adding it results in the set
/// not containing that object. It only supports added and removed, not arbitrary
/// counts.
public struct NegativeSet<T: Hashable> {
    public fileprivate(set) var added: Set<T> = []
    public fileprivate(set) var removed: Set<T> = []
    
    public init() {
    }
    
    public mutating func unionInPlace(_ set: Set<T>) {
        let new = set.fastSubtracting(removed)
        added.formUnion(new)
        removed.fastSubtract(set)
    }
    
    public mutating func subtractInPlace(_ set: Set<T>) {
        let gone = set.fastSubtracting(added)
        removed.formUnion(gone)
        added.fastSubtract(set)
    }
    
    public mutating func removeAll() {
        added.removeAll()
        removed.removeAll()
    }
}
