//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

extension Array {
    func binarySearch(_ lessThan: (Element) -> Bool) -> Int {
        return self[0..<count].binarySearch(lessThan)
    }
    
    mutating func insertSorted<T>(_ element: Element, by keyPath: KeyPath<Element, T>, _ compare: (T, T) -> Bool) -> Int {
        let val = element[keyPath: keyPath]

        let index = binarySearch({ compare($0[keyPath: keyPath], val) })
        if index < count {
            insert(element, at: index)
        } else {
            append(element)
        }
        
        return index
    }

    /// Returns true if the element at the given index is correctly ordered between its adjacent elements
    /// according to the given comparison function.
    func isElementOrdered<T>(at index: Int, by keyPath: KeyPath<Element, T>, _ compare: (T, T) -> Bool) -> Bool {
        precondition(index >= 0 && index < self.count)
        
        let elem = self[index]
        
        let afterLeft: Bool
        if index - 1 >= 0 {
            // See if this item is "after" the item to its left
            let left = self[index - 1]
            afterLeft = compare(left[keyPath: keyPath], elem[keyPath: keyPath])
        } else {
            // This is the first item; we'll treat it as being "after" whatever comes before
            afterLeft = true
        }
        
        let beforeRight: Bool
        if index + 1 < self.count {
            // See if this item is "before" the item to its right
            let right = self[index + 1]
            beforeRight = compare(elem[keyPath: keyPath], right[keyPath: keyPath])
        } else {
            // This is the first item; we'll treat it as being "before" whatever comes after
            beforeRight = true
        }

        return afterLeft && beforeRight
    }
}

extension Array where Element: Comparable {
    func binarySearch(_ element: Element) -> Int {
        return self.binarySearch({ $0 < element })
    }
}

extension ArraySlice {
    func binarySearch(_ lessThan: (Element) -> Bool) -> Int {
        if count == 0 { return startIndex }
        let mid = startIndex + ((endIndex - startIndex) / 2)
        if lessThan(self[mid]) {
            return self[(mid + 1)..<endIndex].binarySearch(lessThan)
        } else {
            return self[startIndex..<mid].binarySearch(lessThan)
        }
    }
}
