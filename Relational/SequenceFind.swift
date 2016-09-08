//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

extension Sequence {
    func find(_ predicate: (Iterator.Element) -> Bool) -> Iterator.Element? {
        for element in self {
            if predicate(element) {
                return element
            }
        }
        return nil
    }
}
