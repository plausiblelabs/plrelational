//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import libRelational
@testable import Binding

class RelationAsyncPropertyTests: BindingTestCase {
    
    func testReadOnlyProperty() {
        let db = makeDB().db
        let sqlr = db.createRelation("animal", scheme: ["id", "name"]).ok!
        let r = ChangeLoggingRelation(baseRelation: sqlr)
        
        let property = r.select(Attribute("id") *== 1).project(["name"]).asyncProperty{ $0.oneString }
        var change: String?
        _ = property.signal.observe({ newValue, _ in change = newValue })

        XCTAssertEqual(property.value, nil)
        XCTAssertEqual(change, nil)

        // TODO: Trigger initial query
//        XCTAssertEqual(property.value, "")
//        XCTAssertEqual(change, nil)

        // TODO: Currently this is synchronous; need to change this test so that it verifies
        // behavior in an asynchronous environment
        r.add(["id": 1, "name": "cat"])
        
        XCTAssertEqual(property.value, "cat")
        XCTAssertEqual(change, "cat")
        change = nil

        r.add(["id": 2, "name": "dog"])
        
        XCTAssertEqual(property.value, "cat")
        XCTAssertEqual(change, nil)
        change = nil

        r.delete(true)
        
        XCTAssertEqual(property.value, "")
        XCTAssertEqual(change, "")
        change = nil
    }
}