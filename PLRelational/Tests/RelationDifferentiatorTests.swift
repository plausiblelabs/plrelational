//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
@testable import PLRelational

class RelationDifferentiatorTests: XCTestCase {
    func testEquijoinDerivative() {
        let a = MakeRelation(["id", "text"],
                             [1, "new"],
                             [2, "blah blah blah"])
            .setDebugName("a")
        let b = MakeRelation(["id", "title"],
                             [1, "NEW"],
                             [2, "Blah Blah Blah"])
            .setDebugName("b")
        
        let joined = a.equijoin(b, matching: ["id": "id"])
            .setDebugName("joined")
        
        let differentiator = RelationDifferentiator(relation: joined)
        let derivative = differentiator.computeDerivative()
        
        derivative.addChange(RelationChange(
            added: MakeRelation(["id", "text"], [1, "new"]),
            removed: MakeRelation(["id", "text"], [1, "old"])), toVariable: a)
        
        derivative.addChange(RelationChange(
            added: MakeRelation(["id", "title"], [1, "NEW"]),
            removed: MakeRelation(["id", "title"], [1, "OLD"])), toVariable: b)
        
        AssertEqual(derivative.change.added, MakeRelation(["id", "text", "title"], [1, "new", "NEW"]))
        AssertEqual(derivative.change.removed, MakeRelation(["id", "text", "title"], [1, "old", "OLD"]))
    }
}
