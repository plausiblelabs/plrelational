//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
@testable import PLRelational

class QueryRunnerTests: XCTestCase {
    func testLargerTree() {
        let a = MakeRelation(["number", "pilot", "equipment"])
        let b = MakeRelation(["number", "pilot", "equipment"], [1, "Jones", "777"])
        let c = MakeRelation(["number", "pilot", "equipment"])
        let d = MakeRelation(["number", "pilot", "equipment"], [2, "Smith", "787"])
        let e = MakeRelation(["number", "pilot", "equipment"])
        let f = MakeRelation(["number", "pilot", "equipment"], [1, "Jones", "777"])
        let g = MakeRelation(["number", "pilot", "equipment"], [3, "Johnson", "797"])
        let h = MakeRelation(["number", "pilot", "equipment"])
        let i = MakeRelation(["number", "pilot", "equipment"], [1, "Jones", "777"])
        let j = MakeRelation(["number", "pilot", "equipment"], [2, "Smith", "787"])
        
        let bc = b.difference(c)
        let abc = a.union(bc)
        let ef = e.difference(f)
        let def = d.difference(ef)
        let abcdef = abc.union(def)
        let hi = h.difference(i)
        let hij = hi.difference(j)
        let ghij = g.difference(hij)
        let abcdefghij = abcdef.union(ghij)
        
        AssertEqual(abcdefghij,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        [1, "Jones", "777"],
                        [2, "Smith", "787"],
                        [3, "Johnson", "797"]))
    }
}
