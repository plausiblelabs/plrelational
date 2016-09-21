//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import libRelational

class PlistDatabaseTests: XCTestCase {
    
    func testRoundtrip() {
        let specs: [PlistDatabase.RelationSpec] = [
            .file(name: "object", path: "objects.plist", scheme: ["id", "name"]),
            .file(name: "doc_item", path: "doc_items.plist", scheme: ["id", "parent", "order"]),
            .directory(name: "object_data", path: "object_data", scheme: ["id", "value"], primaryKey: "id")
        ]
        let dbResult = PlistDatabase.open(specs)
        XCTAssertNil(dbResult.err)
        let db = dbResult.ok!

        let tResult: Result<Void, RelationError> = db.transaction{
            var objects = db["object"]!
            _ = objects.add(["id": 1, "name": "A"])
            return ((), .commit)
        }
        XCTAssertNil(tResult.err)
    }
}
