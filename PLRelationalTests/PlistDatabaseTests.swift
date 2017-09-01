//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import PLRelational

class PlistDatabaseTests: XCTestCase {
    
    var urls: [URL] = []
    
    override func tearDown() {
        super.tearDown()
        
        for url in urls {
            _ = try? FileManager.default.removeItem(at: url)
        }
        urls = []
    }
    
    func tmpURL() -> URL {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        let url = tmp.appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
        urls.append(url)
        return url
    }
    
    func testErrorOnNonexistentFile() {
        let specs: [PlistDatabase.RelationSpec] = [
            .file(name: "a", path: "a.plist", scheme: ["a"], primaryKeys: ["a"])
        ]
        let result = PlistDatabase.open(tmpURL(), specs)
        XCTAssertNotNil(result.err)
    }

    func testRoundtrip() {
        let root = tmpURL()
        let specs: [PlistDatabase.RelationSpec] = [
            .file(name: "object", path: "objects.plist", scheme: ["id", "name"], primaryKeys: ["id"]),
            .file(name: "doc_item", path: "doc_items.plist", scheme: ["id", "parent", "order"], primaryKeys: ["id"]),
            .directory(name: "object_data", path: "object_data", scheme: ["id", "value"], primaryKey: "id")
        ]
        
        let createResult = PlistDatabase.create(root, specs)
        XCTAssertNil(createResult.err)
        let db1 = createResult.ok!

        let addResult: Result<Void, RelationError> = db1.transaction{
            let objects = db1["object"]!
            let objectData = db1["object_data"]!
            let docItems = db1["doc_item"]!
            _ = objects.add(["id": 1, "name": "Group"])
            _ = objects.add(["id": 2, "name": "Page1"])
            _ = objects.add(["id": 3, "name": "Page2"])
            _ = docItems.add(["id": 1, "parent": RelationValue.null, "order": 5.0])
            _ = docItems.add(["id": 2, "parent": 1, "order": 5.0])
            _ = docItems.add(["id": 3, "parent": 1, "order": 7.0])
            _ = objectData.add(["id": 2, "value": "Write about Page1 here."])
            _ = objectData.add(["id": 3, "value": "Write about Page2 here."])
            return ((), .commit)
        }
        XCTAssertNil(addResult.err)
        
        let openResult = PlistDatabase.open(root, specs)
        XCTAssertNil(openResult.err)
        let db2 = openResult.ok!
        
        let docObjectData = db2["object"]!.join(db2["doc_item"]!).join(db2["object_data"]!)
        AssertEqual(
            docObjectData,
            MakeRelation(
                ["id", "name", "parent", "order", "value"],
                [2, "Page1", 1, 5.0, "Write about Page1 here."],
                [3, "Page2", 1, 7.0, "Write about Page2 here."]
            )
        )
    }
}
