//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import libRelational
@testable import Binding

class RelationSignalTests: BindingTestCase {
    
    func testSignal() {
        let db = makeDB().db
        let sqlr = db.createRelation("animal", scheme: ["id", "name"]).ok!
        let r = ChangeLoggingRelation(baseRelation: sqlr)
        
        let signal = r.select(Attribute("id") *== 1).project(["name"]).signal{ $0.oneString }
        var change: String?
        _ = signal.observe({ newValue, _ in change = newValue })
        
        XCTAssertEqual(change, nil)

        // TODO: Trigger initial query

        // TODO: Currently this is synchronous; need to change this test so that it verifies
        // behavior in an asynchronous environment
        r.add(["id": 1, "name": "cat"])
        
        XCTAssertEqual(change, "cat")
        change = nil
        
        r.add(["id": 2, "name": "dog"])
        
        XCTAssertEqual(change, nil)
        change = nil
        
        r.delete(true)
        
        XCTAssertEqual(change, "")
        change = nil
    }
}
