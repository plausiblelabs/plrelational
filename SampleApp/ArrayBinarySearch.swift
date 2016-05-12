//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

extension Array {
    func binarySearch(lessThan: (Element) -> Bool) -> Int {
        return self[0..<count].binarySearch(lessThan)
    }
    
    mutating func insertSorted<T where T: Comparable>(element: Element, _ f: (Element) -> T) -> Int {
        let val = f(element)

        let index = binarySearch({ f($0) < val })
        
        if index < count {
            insert(element, atIndex: index)
        } else {
            append(element)
        }
        
        return index
    }
}

extension Array where Element: Comparable {
    func binarySearch(element: Element) -> Int {
        return self.binarySearch({ $0 < element })
    }
}

extension ArraySlice {
    func binarySearch(lessThan: (Element) -> Bool) -> Int {
        if count == 0 { return startIndex }
        let mid = startIndex + ((endIndex - startIndex) / 2)
        if lessThan(self[mid]) {
            return self[(mid + 1)..<endIndex].binarySearch(lessThan)
        } else {
            return self[startIndex..<mid].binarySearch(lessThan)
        }
    }
}
