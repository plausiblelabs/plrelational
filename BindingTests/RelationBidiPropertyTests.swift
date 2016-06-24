//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import libRelational
@testable import Binding

class RelationBidiPropertyTests: BindingTestCase {

//    func testBidiProperty() {
//        let sqliteDB = makeDB().db
//        let loggingDB = ChangeLoggingDatabase(sqliteDB)
//        let db = TransactionalDatabase(loggingDB)
//        
//        XCTAssertNil(sqliteDB.createRelation("animal", scheme: ["id", "name"]).err)
//        let r = db["animal"]
//        
//        func updateName(newValue: String) {
//            db.transaction{
//                r.update(Attribute("id") *== 1, newValues: ["name": RelationValue(newValue)])
//            }
//        }
//        
//        var snapshotCount = 0
//        var updateCount = 0
//        var commitCount = 0
//        
//        let config: RelationMutationConfig<String> = RelationMutationConfig(
//            snapshot: {
//                snapshotCount += 1
//                return db.takeSnapshot()
//            },
//            update: { newValue in
//                updateCount += 1
//                updateName(newValue)
//            },
//            commit: { _, newValue in
//                commitCount += 1
//                updateName(newValue)
//            }
//        )
//
//        let relationProperty = r.select(Attribute("id") *== 1).project(["name"]).bidiProperty(config, relationToValue: { $0.oneString })
//        var changeObserved = false
//        _ = relationProperty.signal.observe({ _ in changeObserved = true })
//        
//        XCTAssertEqual(relationProperty.get(), "")
//        XCTAssertEqual(snapshotCount, 0)
//        XCTAssertEqual(updateCount, 0)
//        XCTAssertEqual(commitCount, 0)
//        XCTAssertEqual(changeObserved, false)
//        changeObserved = false
//        
//        r.add(["id": 1, "name": "cat"])
//        
//        XCTAssertEqual(relationProperty.get(), "cat")
//        XCTAssertEqual(snapshotCount, 0)
//        XCTAssertEqual(updateCount, 0)
//        XCTAssertEqual(commitCount, 0)
//        XCTAssertEqual(changeObserved, true)
//        changeObserved = false
//
//        let otherProperty = ValueBidiProperty("")
//        otherProperty <~> relationProperty
//        
//        otherProperty.change(newValue: "dog", transient: true)
//        
//        XCTAssertEqual(relationProperty.get(), "dog")
//        XCTAssertEqual(snapshotCount, 1)
//        XCTAssertEqual(updateCount, 1)
//        XCTAssertEqual(commitCount, 0)
//        XCTAssertEqual(changeObserved, true)
//        changeObserved = false
//
//        otherProperty.change(newValue: "dogg", transient: true)
//        
//        XCTAssertEqual(relationProperty.get(), "dogg")
//        XCTAssertEqual(snapshotCount, 1)
//        XCTAssertEqual(updateCount, 2)
//        XCTAssertEqual(commitCount, 0)
//        XCTAssertEqual(changeObserved, true)
//        changeObserved = false
//
//        otherProperty.change(newValue: "dogg", transient: false)
//        
//        // Note: Even when the value to be committed is not actually changing from the
//        // previous transient value, the value still needs to be committed to the
//        // underlying database (although observers will not be notified, since from
//        // their perspective the value is not changing)
//        XCTAssertEqual(relationProperty.get(), "dogg")
//        XCTAssertEqual(snapshotCount, 1)
//        XCTAssertEqual(updateCount, 2)
//        XCTAssertEqual(commitCount, 1)
//        XCTAssertEqual(changeObserved, false)
//        changeObserved = false
//
//        otherProperty.change(newValue: "ant", transient: false)
//        
//        XCTAssertEqual(relationProperty.get(), "ant")
//        XCTAssertEqual(snapshotCount, 2)
//        XCTAssertEqual(updateCount, 2)
//        XCTAssertEqual(commitCount, 2)
//        XCTAssertEqual(changeObserved, true)
//        changeObserved = false
//        
//        r.delete(true)
//        
//        XCTAssertEqual(relationProperty.get(), "")
//        XCTAssertEqual(snapshotCount, 2)
//        XCTAssertEqual(updateCount, 2)
//        XCTAssertEqual(commitCount, 2)
//        XCTAssertEqual(changeObserved, true)
//        changeObserved = false
//    }
}
