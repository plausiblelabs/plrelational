//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import PLRelational
@testable import PLRelationalCombine

class RelationChangeSummaryTests: CombineTestCase {

    func testNegativeSetSummary() {
        let added: [Row] = [
            ["id": 1, "name": "alice"],
            ["id": 2, "name": "bob"],
            ["id": 3, "name": "carlos"]
        ]
        
        let removed: [Row] = [
            ["id": 3, "name": "charles"],
            ["id": 4, "name": "donald"]
        ]
        
        var set = RowChange()
        set.unionInPlace(Set(added))
        set.subtractInPlace(Set(removed))
        let summary = set.summary(idAttr: "id")
        
        let addedRows: Set<Row> = [
            ["id": 1, "name": "alice"],
            ["id": 2, "name": "bob"]
        ]
        let updatedRows: Set<Row> = [
            ["id": 3, "name": "carlos"]
        ]
        let deletedRows: Set<Row> = [
            ["id": 4, "name": "donald"]
        ]
        
        XCTAssertEqual(Set(summary.added), addedRows)
        XCTAssertEqual(Set(summary.updated), updatedRows)
        XCTAssertEqual(Set(summary.deleted), deletedRows)
    }
}
