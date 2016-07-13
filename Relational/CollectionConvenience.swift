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

public extension MutableCollectionType {
    mutating func mutatingForEach(f: (inout Generator.Element) -> Void) {
        for i in indices {
            f(&self[i])
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

public extension Array where Element: Comparable {
    /// Sort the array in place, ordered smallest to largest. Optimized for small arrays.
    /// For larger arrays, it just calls through to sortInPlace.
    mutating func fastSmallSortInPlace() {
        switch count {
        case 0, 1:
            return
            
        case 2:
            if self[0] > self[1] {
                swap(&self[0], &self[1])
            }
            
        default:
            sortInPlace()
        }
    }
}

public extension Array where Element: Equatable {
    func indexesOf(toFind: Element) -> [Int] {
        switch count {
        case 0: return []
        case 1 where self[0] == toFind:
            return [0]
        case 1:
            return []
        case 2 where self[0] == toFind && self[1] == toFind:
            return [0, 1]
        case 2 where self[0] == toFind:
            return [0]
        case 2 where self[1] == toFind:
            return [1]
        case 2:
            return []
        default:
            var result: [Int] = []
            result.reserveCapacity(4)
            
            for (index, element) in self.enumerate() {
                if element == toFind {
                    result.append(index)
                }
            }
            
            return result
        }
    }
}
