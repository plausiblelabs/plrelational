//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

extension Array {
    func binarySearch(_ lessThan: (Element) -> Bool) -> Int {
        return self[0..<count].binarySearch(lessThan)
    }
    
    mutating func insertSorted<T>(_ element: Element, by keyPath: KeyPath<Element, T>, _ compare: (T, T) -> Bool) -> Int where T: Comparable {
        let val = element[keyPath: keyPath]

        let index = binarySearch({ compare($0[keyPath: keyPath], val) })
        if index < count {
            insert(element, at: index)
        } else {
            append(element)
        }
        
        return index
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
