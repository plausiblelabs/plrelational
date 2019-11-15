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
        let summary = set.summary(idAttr: "id", { $0 })
        
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
    
    func testNegativeSetSummaryWithMap() {
        let added: [Row] = [
            ["id": 1, "name": "alice"],
            ["id": 2, "name": "bob"],
            ["id": 3, "name": "carlos"]
        ]
        
        let removed: [Row] = [
            ["id": 3, "name": "charles"],
            ["id": 4, "name": "donald"]
        ]
        
        struct Item: Hashable, Equatable {
            let id: Int64
            let name: String
        }
        
        var set = RowChange()
        set.unionInPlace(Set(added))
        set.subtractInPlace(Set(removed))
        let summary = set.summary(idAttr: "id", {
            Item(id: $0["id"].get()!, name: $0["name"].get()!)
        })
        
        let addedItems: Set<Item> = [
            Item(id: 1, name: "alice"),
            Item(id: 2, name: "bob")
        ]
        let updatedItems: Set<Item> = [
            Item(id: 3, name: "carlos")
        ]
        let deletedItems: Set<Item> = [
            Item(id: 4, name: "donald")
        ]
        
        XCTAssertEqual(Set(summary.added), addedItems)
        XCTAssertEqual(Set(summary.updated), updatedItems)
        XCTAssertEqual(Set(summary.deleted), deletedItems)
    }
}
