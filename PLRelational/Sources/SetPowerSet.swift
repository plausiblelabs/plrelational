//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

extension Set {
    var powerSet: Set<Set<Element>> {
        if count == 0 { return [[]] }
        let first = self.first!
        let rest = self.subtracting([first])
        let restPowerSet = rest.powerSet
        return restPowerSet.union(restPowerSet.map({ $0.union([first]) }))
    }
}
