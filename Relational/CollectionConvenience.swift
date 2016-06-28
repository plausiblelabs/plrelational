//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

public extension RangeReplaceableCollectionType where Generator.Element: Equatable {
    mutating func remove(element: Generator.Element) {
        if let index = indexOf(element) {
            removeAtIndex(index)
        }
    }
}
    
public extension RangeReplaceableCollectionType {
    /// Remove ONE element matching the predicate. Don't call this if there's more than one,
    /// or you'll just confuse yourself.
    mutating func removeOne(predicate: Generator.Element -> Bool) {
        if let index = indexOf(predicate) {
            removeAtIndex(index)
        }
    }
}

public extension CollectionType where Generator.Element: Equatable {
    func indexesOf(element: Generator.Element) -> [Index] {
        return indices.filter({ self[$0] == element })
    }
}

public extension MutableCollectionType where Generator.Element: Equatable {
    mutating func replace(element: Generator.Element, with: Generator.Element) {
        for i in indices {
            if self[i] == element {
                self[i] = with
            }
        }
    }
}

public extension SequenceType {
    func all(@noescape predicate: Generator.Element -> Bool) -> Bool {
        for elt in self {
            if !predicate(elt) {
                return false
            }
        }
        return true
    }
}
