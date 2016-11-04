//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import PLRelational
@testable import Binding

class RelationChangePartsTests: BindingTestCase {
    
    func testRelationChangeParts() {
        let added = MakeRelation(
            ["id", "name"],
            [1, "alice"],
            [2, "bob"],
            [3, "carlos"])

        let removed = MakeRelation(
            ["id", "name"],
            [3, "charles"],
            [4, "donald"])

        let change = RelationChange(added: added, removed: removed)
        let parts = change.parts("id")
        
        let addedRows: Set<Row> = [
            ["id": 1, "name": "alice"],
            ["id": 2, "name": "bob"]
        ]
        let updatedRows: Set<Row> = [
            ["id": 3, "name": "carlos"]
        ]
        let deletedIDs: Set<RelationValue> = [
            4
        ]

        XCTAssertEqual(Set(parts.addedRows), addedRows)
        XCTAssertEqual(Set(parts.updatedRows), updatedRows)
        XCTAssertEqual(Set(parts.deletedIDs), deletedIDs)
    }
    
    func testNegativeSetParts() {
        let added: [Row] = [
            ["id": 1, "name": "alice"],
            ["id": 2, "name": "bob"],
            ["id": 3, "name": "carlos"]
        ]
        
        let removed: [Row] = [
            ["id": 3, "name": "charles"],
            ["id": 4, "name": "donald"]
        ]
        
        var set = NegativeSet<Row>()
        set.unionInPlace(Set(added))
        set.subtractInPlace(Set(removed))
        let parts = partsOf(set, idAttr: "id")
        
        let addedRows: Set<Row> = [
            ["id": 1, "name": "alice"],
            ["id": 2, "name": "bob"]
        ]
        let updatedRows: Set<Row> = [
            ["id": 3, "name": "carlos"]
        ]
        let deletedIDs: Set<RelationValue> = [
            4
        ]
        
        XCTAssertEqual(Set(parts.addedRows), addedRows)
        XCTAssertEqual(Set(parts.updatedRows), updatedRows)
        XCTAssertEqual(Set(parts.deletedIDs), deletedIDs)
    }
}
