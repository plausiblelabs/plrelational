//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import libRelational
@testable import Binding

class RelationObservableValueTests: BindingTestCase {
    
//    func testObservable() {
//        let db = makeDB().db
//        let sqlr = db.createRelation("animal", scheme: ["id", "name"]).ok!
//        let r = ChangeLoggingRelation(baseRelation: sqlr)
//
//        let observable = r.select(Attribute("id") *== 1).project(["name"]).observable{ $0.oneString }
//        var changeObserved = false
//        _ = observable.addChangeObserver({ _ in changeObserved = true })
//        
//        XCTAssertEqual(observable.value, "")
//        XCTAssertEqual(changeObserved, false)
//        changeObserved = false
//        
//        r.add(["id": 1, "name": "cat"])
//        
//        XCTAssertEqual(observable.value, "cat")
//        XCTAssertEqual(changeObserved, true)
//        changeObserved = false
//        
//        r.add(["id": 2, "name": "dog"])
//
//        XCTAssertNotNil(observable.value)
//        XCTAssertEqual(observable.value, "cat")
//        XCTAssertEqual(changeObserved, false)
//        changeObserved = false
//        
//        r.delete(true)
//        
//        XCTAssertEqual(observable.value, "")
//        XCTAssertEqual(changeObserved, true)
//        changeObserved = false
//    }
//    
//    func testEmpty() {
//        let db = makeDB().db
//        let sqlr = db.createRelation("animal", scheme: ["id", "name"]).ok!
//        let r = ChangeLoggingRelation(baseRelation: sqlr)
//
//        let observable = r.empty
//        var changeObserved = false
//        _ = observable.addChangeObserver({ _ in changeObserved = true })
//        
//        XCTAssertTrue(observable.value)
//        XCTAssertEqual(changeObserved, false)
//        changeObserved = false
//
//        r.add(["id": 1, "name": "cat"])
//        
//        XCTAssertFalse(observable.value)
//        XCTAssertEqual(changeObserved, true)
//        changeObserved = false
//
//        r.add(["id": 2, "name": "dog"])
//        
//        // Verify that observers are not notified when observable value has not actually changed
//        XCTAssertFalse(observable.value)
//        XCTAssertEqual(changeObserved, false)
//        changeObserved = false
//
//        r.delete(true)
//
//        XCTAssertTrue(observable.value)
//        XCTAssertEqual(changeObserved, true)
//        changeObserved = false
//    }
//    
//    func testNonEmpty() {
//        let db = makeDB().db
//        let sqlr = db.createRelation("animal", scheme: ["id", "name"]).ok!
//        let r = ChangeLoggingRelation(baseRelation: sqlr)
//        
//        let observable = r.nonEmpty
//        var changeObserved = false
//        _ = observable.addChangeObserver({ _ in changeObserved = true })
//        
//        XCTAssertFalse(observable.value)
//        XCTAssertEqual(changeObserved, false)
//        changeObserved = false
//        
//        r.add(["id": 1, "name": "cat"])
//        
//        XCTAssertTrue(observable.value)
//        XCTAssertEqual(changeObserved, true)
//        changeObserved = false
//        
//        r.add(["id": 2, "name": "dog"])
//        
//        // Verify that observers are not notified when observable value has not actually changed
//        XCTAssertTrue(observable.value)
//        XCTAssertEqual(changeObserved, false)
//        changeObserved = false
//        
//        r.delete(true)
//        
//        XCTAssertFalse(observable.value)
//        XCTAssertEqual(changeObserved, true)
//        changeObserved = false
//    }
//    
//    func testWhenNotEmpty() {
//        let db = makeDB().db
//        let sqlr = db.createRelation("animal", scheme: ["id", "name"]).ok!
//        let r = ChangeLoggingRelation(baseRelation: sqlr)
//
//        var counter: Int = 0
//        struct Thing {
//            let id: Int
//        }
//        
//        let observable = r.whenNonEmpty{ _ -> Thing in counter += 1; return Thing(id: counter) }
//        var changeObserved = false
//        _ = observable.addChangeObserver({ _ in changeObserved = true })
//        
//        XCTAssertNil(observable.value)
//        XCTAssertEqual(changeObserved, false)
//        changeObserved = false
//        
//        r.add(["id": 1, "name": "cat"])
//        
//        XCTAssertNotNil(observable.value)
//        XCTAssertEqual(observable.value!.id, 1)
//        XCTAssertEqual(changeObserved, true)
//        changeObserved = false
//        
//        r.add(["id": 2, "name": "dog"])
//        
//        XCTAssertNotNil(observable.value)
//        XCTAssertEqual(observable.value!.id, 1)
//        XCTAssertEqual(changeObserved, false)
//        changeObserved = false
//        
//        r.delete(true)
//        
//        XCTAssertNil(observable.value)
//        XCTAssertEqual(changeObserved, true)
//        changeObserved = false
//        
//        r.add(["id": 3, "name": "fish"])
//        
//        XCTAssertNotNil(observable.value)
//        XCTAssertEqual(observable.value!.id, 2)
//        XCTAssertEqual(changeObserved, true)
//        changeObserved = false
//    }
//    
//    func testStringWhenMulti() {
//        let db = makeDB().db
//        let sqlr = db.createRelation("animal", scheme: ["id", "name"]).ok!
//        let r = ChangeLoggingRelation(baseRelation: sqlr)
//        
//        let observable = r.project(["name"]).stringWhenMulti("multi")
//        var changeObserved = false
//        _ = observable.addChangeObserver({ _ in changeObserved = true })
//        
//        XCTAssertEqual(observable.value, "")
//        XCTAssertEqual(changeObserved, false)
//        changeObserved = false
//        
//        r.add(["id": 1, "name": "cat"])
//        
//        // Verify that observers are not notified when observable value has not actually changed
//        XCTAssertEqual(observable.value, "")
//        XCTAssertEqual(changeObserved, false)
//        changeObserved = false
//        
//        r.add(["id": 2, "name": "dog"])
//        
//        XCTAssertEqual(observable.value, "multi")
//        XCTAssertEqual(changeObserved, true)
//        changeObserved = false
//
//        // Verify that value is considered "multi" when there is a single non-NULL value and a
//        // single NULL value
//        r.update(Attribute("id") *== 2, newValues: ["name": .NULL])
//
//        XCTAssertEqual(observable.value, "multi")
//        XCTAssertEqual(changeObserved, false)
//        changeObserved = false
//
//        r.delete(true)
//        
//        XCTAssertEqual(observable.value, "")
//        XCTAssertEqual(changeObserved, true)
//        changeObserved = false
//    }
}
