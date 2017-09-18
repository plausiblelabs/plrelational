//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

/// :nodoc: Implementation detail (will be made non-public eventually)
public extension RangeReplaceableCollection where Iterator.Element: Equatable {
    mutating func remove(_ element: Iterator.Element) {
        if let index = index(of: element) {
            self.remove(at: index)
        }
    }
}
    
/// :nodoc: Implementation detail (will be made non-public eventually)
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

/// :nodoc: Implementation detail (will be made non-public eventually)
public extension Collection where Iterator.Element: Equatable {
    func indexesOf(_ element: Iterator.Element) -> [Index] {
        return indices.filter({ self[$0] == element })
    }
}

/// :nodoc: Implementation detail (will be made non-public eventually)
public extension MutableCollection where Iterator.Element: Equatable {
    mutating func replace(_ element: Iterator.Element, with: Iterator.Element) {
        for i in indices {
            if self[i] == element {
                self[i] = with
            }
        }
    }
}

/// :nodoc: Implementation detail (will be made non-public eventually)
public extension MutableCollection {
    mutating func mutatingForEach(_ f: (inout Iterator.Element) -> Void) {
        for i in indices {
            f(&self[i])
        }
    }
}

/// :nodoc: Implementation detail (will be made non-public eventually)
public extension Dictionary {
    mutating func mutatingForEach(_ f: (inout Value) -> Void) {
        for k in keys {
            f(&self[k]!)
        }
    }
}

/// :nodoc: Implementation detail (will be made non-public eventually)
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

/// :nodoc: Implementation detail (will be made non-public eventually)
public extension Array where Element: Comparable {
    /// Sort the array in place, ordered smallest to largest. Optimized for small arrays.
    /// For larger arrays, it just calls through to sortInPlace.
    mutating func fastSmallSortInPlace() {
        switch count {
        case 0, 1:
            return
            
        case 2:
            if self[0] > self[1] {
                self.swapAt(0, 1)
            }
            
        default:
            sort()
        }
    }
}

/// :nodoc: Implementation detail (will be made non-public eventually)
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

/// :nodoc: Implementation detail (will be made non-public eventually)
public func +<T>(lhs: Set<T>, rhs: Set<T>) -> Set<T> {
    return lhs.union(rhs)
}

/// :nodoc: Implementation detail (will be made non-public eventually)
public func -<T>(lhs: Set<T>, rhs: Set<T>) -> Set<T> {
    return lhs.fastSubtracting(rhs)
}
