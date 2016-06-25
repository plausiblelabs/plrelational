//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import libRelational
@testable import Binding

class RelationPropertyTests: BindingTestCase {
    
    func testProperty() {
        let db = makeDB().db
        let sqlr = db.createRelation("animal", scheme: ["id", "name"]).ok!
        let r = ChangeLoggingRelation(baseRelation: sqlr)
        
        let property = r.select(Attribute("id") *== 1).project(["name"]).property{ $0.oneString }
        var changeObserved = false
        _ = property.signal.observe({ _ in changeObserved = true })
        
        XCTAssertEqual(property.value, "")
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        r.add(["id": 1, "name": "cat"])
        
        XCTAssertEqual(property.value, "cat")
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        r.add(["id": 2, "name": "dog"])
        
        XCTAssertNotNil(property.value)
        XCTAssertEqual(property.value, "cat")
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        r.delete(true)
        
        XCTAssertEqual(property.value, "")
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
    }
    
    func testEmpty() {
        let db = makeDB().db
        let sqlr = db.createRelation("animal", scheme: ["id", "name"]).ok!
        let r = ChangeLoggingRelation(baseRelation: sqlr)
        
        let property = r.empty
        var changeObserved = false
        _ = property.signal.observe({ _ in changeObserved = true })
        
        XCTAssertTrue(property.value)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        r.add(["id": 1, "name": "cat"])
        
        XCTAssertFalse(property.value)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        r.add(["id": 2, "name": "dog"])
        
        // Verify that observers are not notified when property value has not actually changed
        XCTAssertFalse(property.value)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        r.delete(true)
        
        XCTAssertTrue(property.value)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
    }
    
    func testNonEmpty() {
        let db = makeDB().db
        let sqlr = db.createRelation("animal", scheme: ["id", "name"]).ok!
        let r = ChangeLoggingRelation(baseRelation: sqlr)
        
        let property = r.nonEmpty
        var changeObserved = false
        _ = property.signal.observe({ _ in changeObserved = true })
        
        XCTAssertFalse(property.value)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        r.add(["id": 1, "name": "cat"])
        
        XCTAssertTrue(property.value)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        r.add(["id": 2, "name": "dog"])
        
        // Verify that observers are not notified when property value has not actually changed
        XCTAssertTrue(property.value)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        r.delete(true)
        
        XCTAssertFalse(property.value)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
    }
    
    func testWhenNotEmpty() {
        let db = makeDB().db
        let sqlr = db.createRelation("animal", scheme: ["id", "name"]).ok!
        let r = ChangeLoggingRelation(baseRelation: sqlr)
        
        var counter: Int = 0
        struct Thing {
            let id: Int
        }
        
        let property = r.whenNonEmpty{ _ -> Thing in counter += 1; return Thing(id: counter) }
        var changeObserved = false
        _ = property.signal.observe({ _ in changeObserved = true })
        
        XCTAssertNil(property.value)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        r.add(["id": 1, "name": "cat"])
        
        XCTAssertNotNil(property.value)
        XCTAssertEqual(property.value!.id, 1)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        r.add(["id": 2, "name": "dog"])
        
        XCTAssertNotNil(property.value)
        XCTAssertEqual(property.value!.id, 1)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        r.delete(true)
        
        XCTAssertNil(property.value)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        r.add(["id": 3, "name": "fish"])
        
        XCTAssertNotNil(property.value)
        XCTAssertEqual(property.value!.id, 2)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
    }
    
    func testStringWhenMulti() {
        let db = makeDB().db
        let sqlr = db.createRelation("animal", scheme: ["id", "name"]).ok!
        let r = ChangeLoggingRelation(baseRelation: sqlr)
        
        let property = r.project(["name"]).stringWhenMulti("multi")
        var changeObserved = false
        _ = property.signal.observe({ _ in changeObserved = true })
        
        XCTAssertEqual(property.value, "")
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        r.add(["id": 1, "name": "cat"])
        
        // Verify that observers are not notified when property value has not actually changed
        XCTAssertEqual(property.value, "")
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        r.add(["id": 2, "name": "dog"])
        
        XCTAssertEqual(property.value, "multi")
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        // Verify that value is considered "multi" when there is a single non-NULL value and a
        // single NULL value
        r.update(Attribute("id") *== 2, newValues: ["name": .NULL])
        
        XCTAssertEqual(property.value, "multi")
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        r.delete(true)
        
        XCTAssertEqual(property.value, "")
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
    }
}
