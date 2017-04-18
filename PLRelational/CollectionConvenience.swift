//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

public extension RangeReplaceableCollection where Iterator.Element: Equatable {
    mutating func remove(_ element: Iterator.Element) {
        if let index = index(of: element) {
            self.remove(at: index)
        }
    }
}
    
public extension RangeReplaceableCollection {
    /// Remove ONE element matching the predicate. Don't call this if there's more than one,
    /// or you'll just confuse yourself.
    mutating func removeOne(_ predicate: (Iterator.Element) -> Bool) {
        if let index = index(where: predicate) {
            self.remove(at: index)
        }
    }
    
    /// Append the element if it's non-nil, and ignore the call if it's nil.
    mutating func appendNonNil(_ element: Iterator.Element?) {
        if let element = element {
            self.append(element)
        }
    }
}

public extension Collection where Iterator.Element: Equatable, Indices.Iterator.Element == Index {
    func indexesOf(_ element: Iterator.Element) -> [Index] {
        return indices.filter({ self[$0] == element })
    }
}

public extension MutableCollection where Iterator.Element: Equatable, Indices.Iterator.Element == Index {
    mutating func replace(_ element: Iterator.Element, with: Iterator.Element) {
        for i in indices {
            if self[i] == element {
                self[i] = with
            }
        }
    }
}

public extension MutableCollection where Indices.Iterator.Element == Index{
    mutating func mutatingForEach(_ f: (inout Iterator.Element) -> Void) {
        for i in indices {
            f(&self[i])
        }
    }
}

public extension Dictionary {
    mutating func mutatingForEach(_ f: (inout Value) -> Void) {
        for k in keys {
            f(&self[k]!)
        }
    }
}

public extension Sequence {
    func all(_ predicate: (Iterator.Element) -> Bool) -> Bool {
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
            sort()
        }
    }
}

public extension Array where Element: Equatable {
    func indexesOf(_ toFind: Element) -> [Int] {
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
            
            for (index, element) in self.enumerated() {
                if element == toFind {
                    result.append(index)
                }
            }
            
            return result
        }
    }
}

public func +<T: Hashable>(lhs: Set<T>, rhs: Set<T>) -> Set<T> {
    return lhs.union(rhs)
}

public func -<T: Hashable>(lhs: Set<T>, rhs: Set<T>) -> Set<T> {
    return lhs.fastSubtracting(rhs)
}
