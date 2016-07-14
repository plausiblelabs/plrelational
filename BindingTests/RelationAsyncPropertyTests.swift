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

        var willChangeCount = 0
        var didChangeCount = 0
        var change: String?

        let runloop = CFRunLoopGetCurrent()
        let group = dispatch_group_create()

        let property = r.select(Attribute("id") *== 1).project(["name"]).asyncProperty{ $0.signal{ $0.oneString($1) } }
        _ = property.signal.observe(SignalObserver(
            valueWillChange: {
                willChangeCount += 1
            },
            valueChanging: { newValue, _ in change = newValue },
            valueDidChange: {
                didChangeCount += 1
                dispatch_group_leave(group)
                CFRunLoopStop(runloop)
            }
        ))

        // Verify that property value remains nil until we actually trigger the query
        XCTAssertEqual(property.value, nil)
        XCTAssertEqual(willChangeCount, 0)
        XCTAssertEqual(didChangeCount, 0)
        XCTAssertEqual(change, nil)

        // Trigger the async query and wait for it to complete
        dispatch_group_enter(group)
        property.start()
        CFRunLoopRun()
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER)

        // Verify that value was fetched
        XCTAssertEqual(property.value, "")
        XCTAssertEqual(willChangeCount, 1)
        XCTAssertEqual(didChangeCount, 1)
        XCTAssertEqual(change, "")

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
    
    func testReadWriteProperty() {
        let sqliteDB = makeDB().db
        let loggingDB = ChangeLoggingDatabase(sqliteDB)
        let db = TransactionalDatabase(loggingDB)
        
        XCTAssertNil(sqliteDB.createRelation("animal", scheme: ["id", "name"]).err)
        let r = db["animal"]
        
        func updateName(newValue: String) {
            db.transaction{
                r.update(Attribute("id") *== 1, newValues: ["name": RelationValue(newValue)])
            }
        }
        
        var snapshotCount = 0
        var updateCount = 0
        var commitCount = 0
        
        let config: RelationMutationConfig<String> = RelationMutationConfig(
            snapshot: {
                snapshotCount += 1
                return db.takeSnapshot()
            },
            update: { newValue in
                updateCount += 1
                updateName(newValue)
            },
            commit: { _, newValue in
                commitCount += 1
                updateName(newValue)
            }
        )
        
        let nameRelation = r.select(Attribute("id") *== 1).project(["name"])
        let nameProperty = nameRelation.asyncProperty(config, signal: nameRelation.signal{ $0.oneString($1) })
        var changeObserved = false
        _ = nameProperty.signal.observe({ _ in changeObserved = true })
        
        XCTAssertEqual(nameProperty.value, nil)
        XCTAssertEqual(snapshotCount, 0)
        XCTAssertEqual(updateCount, 0)
        XCTAssertEqual(commitCount, 0)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        // TODO: Trigger initial query
        
        // TODO: Currently this is synchronous; need to change this test so that it verifies
        // behavior in an asynchronous environment
        r.add(["id": 1, "name": "cat"])
        
        XCTAssertEqual(nameProperty.value, "cat")
        XCTAssertEqual(snapshotCount, 0)
        XCTAssertEqual(updateCount, 0)
        XCTAssertEqual(commitCount, 0)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
//        // TODO: We use `valueChanging: { true }` here to simulate how TextField.string works
//        // (since that one is an ExternalValueProperty) relative to the "Note" comment below.
//        // Possibly a better way to deal with all this would be to actually notify observers
//        // in the the case where the value is not changing but the transient flag *is* changing.
//        let otherProperty = mutableValueProperty("", valueChanging: { _ in true })
//        otherProperty <~> nameProperty
//        
//        otherProperty.change("dog", transient: true)
//        
//        XCTAssertEqual(nameProperty.value, "dog")
//        XCTAssertEqual(snapshotCount, 1)
//        XCTAssertEqual(updateCount, 1)
//        XCTAssertEqual(commitCount, 0)
//        XCTAssertEqual(changeObserved, true)
//        changeObserved = false
//        
//        otherProperty.change("dogg", transient: true)
//        
//        XCTAssertEqual(nameProperty.value, "dogg")
//        XCTAssertEqual(snapshotCount, 1)
//        XCTAssertEqual(updateCount, 2)
//        XCTAssertEqual(commitCount, 0)
//        XCTAssertEqual(changeObserved, true)
//        changeObserved = false
//        
//        otherProperty.change("dogg", transient: false)
//        
//        // Note: Even when the value to be committed is not actually changing from the
//        // previous transient value, the value still needs to be committed to the
//        // underlying database (although observers will not be notified, since from
//        // their perspective the value is not changing)
//        // TODO: This only works because of the `valueChanging` hack for `otherProperty`, see TODO above.
//        XCTAssertEqual(nameProperty.value, "dogg")
//        XCTAssertEqual(snapshotCount, 1)
//        XCTAssertEqual(updateCount, 2)
//        XCTAssertEqual(commitCount, 1)
//        XCTAssertEqual(changeObserved, false)
//        changeObserved = false
//        
//        otherProperty.change("ant", transient: false)
//        
//        XCTAssertEqual(nameProperty.value, "ant")
//        XCTAssertEqual(snapshotCount, 2)
//        XCTAssertEqual(updateCount, 2)
//        XCTAssertEqual(commitCount, 2)
//        XCTAssertEqual(changeObserved, true)
//        changeObserved = false
//        
//        r.delete(true)
//        
//        XCTAssertEqual(nameProperty.value, "")
//        XCTAssertEqual(snapshotCount, 2)
//        XCTAssertEqual(updateCount, 2)
//        XCTAssertEqual(commitCount, 2)
//        XCTAssertEqual(changeObserved, true)
//        changeObserved = false
    }
}
