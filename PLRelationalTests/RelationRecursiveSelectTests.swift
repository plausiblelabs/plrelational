//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import PLRelational

class RelationRecursiveSelectTests: DBTestCase {
    
    func testRecursiveSelect() {
        let r = MakeRelation(
            ["id", "name", "related_ids"],
            [1, "one",   "2 3"],
            [2, "two",   "3 4"],
            [3, "three", "4"],
            [4, "four",  ""],
            [5, "five",  ""]
        )
        
        let group = DispatchGroup()
        group.enter()

        var names: [RelationValue: String]?
        
        r.recursiveSelect(
            idAttr: "id",
            initialID: 1,
            rowCallback: { row -> Result<(String, [RelationValue]), RelationError> in
                let name: String = row["name"].get()!
                let relatedIDsString: String = row["related_ids"].get()!
                let relatedIDs = relatedIDsString
                    .characters
                    .split{ $0 == " " }
                    .map{ RelationValue(Int64(String($0))!) }
                let result: (String, [RelationValue]) = (name, relatedIDs)
                return .Ok(result)
            },
            completionCallback: { result in
                XCTAssertNil(result.err)
                names = result.ok!
                group.leave()
            }
        )
        
        let runloop = CFRunLoopGetCurrent()!
        group.notify(queue: DispatchQueue.global(), execute: { runloop.async({ CFRunLoopStop(runloop) }) })
        CFRunLoopRun()
        
        XCTAssertEqual(
            names!,
            [
                1: "one",
                2: "two",
                3: "three",
                4: "four"
            ]
        )
    }
}
