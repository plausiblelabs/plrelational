//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import libRelational
@testable import Binding

class RelationAsyncPropertyTests: BindingTestCase {
    
    func testAsyncReadOnlyProperty() {
        let sqliteDB = makeDB().db
        let sqlr = sqliteDB.createRelation("animal", scheme: ["id", "name"]).ok!
        let db = TransactionalDatabase(sqliteDB)
        let r = db["animal"]

        var willChangeCount = 0
        var didChangeCount = 0
        var changes: [String] = []

        let runloop = CFRunLoopGetCurrent()
        let group = dispatch_group_create()

        func awaitCompletion(f: () -> Void) {
            dispatch_group_enter(group)
            f()
            CFRunLoopRun()
            dispatch_group_wait(group, DISPATCH_TIME_FOREVER)
        }

        let property = r.select(Attribute("id") *== 1).project(["name"]).asyncProperty{ $0.signal{ $0.oneString($1) } }
        _ = property.signal.observe(SignalObserver(
            valueWillChange: {
                willChangeCount += 1
            },
            valueChanging: { newValue, _ in changes.append(newValue) },
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
        XCTAssertEqual(changes, [])

        // Trigger the async query and wait for it to complete, then verify that value was updated
        awaitCompletion{ property.start() }
        XCTAssertEqual(property.value, "")
        XCTAssertEqual(willChangeCount, 1)
        XCTAssertEqual(didChangeCount, 1)
        XCTAssertEqual(changes, [""])

//        // Perform an async update to the underlying relation
//        awaitCompletion{ r.asyncAdd(["id": 1, "name": "cat"]) }
//        XCTAssertEqual(property.value, "cat")
//        XCTAssertEqual(willChangeCount, 2)
//        XCTAssertEqual(didChangeCount, 2)
//        XCTAssertEqual(changes, ["", "cat"])
//        
//        // Perform another async update to the underlying relation (except this one isn't relevant to the
//        // `select` that our signal is built on, so the signal shouldn't deliver a change)
//        awaitCompletion{ r.asyncAdd(["id": 2, "name": "dog"]) }
//        XCTAssertEqual(property.value, "cat")
//        XCTAssertEqual(willChangeCount, 3)
//        XCTAssertEqual(didChangeCount, 3)
//        XCTAssertEqual(changes, ["", "cat"])
//        
//        // Perform an async delete-all-rows on the underlying relation
//        awaitCompletion{ r.asyncDelete(true) }
//        XCTAssertEqual(property.value, "")
//        XCTAssertEqual(willChangeCount, 4)
//        XCTAssertEqual(didChangeCount, 4)
//        XCTAssertEqual(changes, ["", "cat", ""])
    }
    
    func testAsyncReadWriteProperty() {
        let sqliteDB = makeDB().db
        let sqlr = sqliteDB.createRelation("animal", scheme: ["id", "name"]).ok!
        let db = TransactionalDatabase(sqliteDB)
        let r = db["animal"]
        
        var willChangeCount = 0
        var didChangeCount = 0
        var changes: [String] = []
        
        let runloop = CFRunLoopGetCurrent()
        let group = dispatch_group_create()

        func updateName(newValue: String) {
            db.transaction{
                r.update(Attribute("id") *== 1, newValues: ["name": RelationValue(newValue)])
            }
        }
        
        func awaitCompletion(f: () -> Void) {
            dispatch_group_enter(group)
            f()
            CFRunLoopRun()
            dispatch_group_wait(group, DISPATCH_TIME_FOREVER)
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

        _ = nameProperty.signal.observe(SignalObserver(
            valueWillChange: {
                willChangeCount += 1
            },
            valueChanging: { newValue, _ in changes.append(newValue) },
            valueDidChange: {
                didChangeCount += 1
                dispatch_group_leave(group)
                CFRunLoopStop(runloop)
            }
        ))

        // Verify that property value remains nil until we actually trigger the query
        XCTAssertEqual(nameProperty.value, nil)
        XCTAssertEqual(willChangeCount, 0)
        XCTAssertEqual(didChangeCount, 0)
        XCTAssertEqual(changes, [])
        XCTAssertEqual(snapshotCount, 0)
        XCTAssertEqual(updateCount, 0)
        XCTAssertEqual(commitCount, 0)
        
        // Trigger the async query and wait for it to complete, then verify that value was updated
        awaitCompletion{ nameProperty.start() }
        XCTAssertEqual(nameProperty.value, "")
        XCTAssertEqual(willChangeCount, 1)
        XCTAssertEqual(didChangeCount, 1)
        XCTAssertEqual(changes, [""])
        XCTAssertEqual(snapshotCount, 0)
        XCTAssertEqual(updateCount, 0)
        XCTAssertEqual(commitCount, 0)

//        // Perform an async update to the underlying relation
//        awaitCompletion{ r.asyncAdd(["id": 1, "name": "cat"]) }
//        XCTAssertEqual(nameProperty.value, "cat")
//
//        // TODO: Currently this is synchronous; need to change this test so that it verifies
//        // behavior in an asynchronous environment
//        r.add(["id": 1, "name": "cat"])
//        XCTAssertEqual(willChangeCount, 2)
//        XCTAssertEqual(didChangeCount, 2)
//        XCTAssertEqual(changes, ["", "cat"])
//        XCTAssertEqual(snapshotCount, 0)
//        XCTAssertEqual(updateCount, 0)
//        XCTAssertEqual(commitCount, 0)
        
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
    
    func testBindToAsyncReadOnlyProperty() {
        let db = makeDB().db
        let sqlr = db.createRelation("animal", scheme: ["id", "name"]).ok!
        let r = ChangeLoggingRelation(baseRelation: sqlr)
        
        // Create an async property from the relation
        let rhs = r.select(Attribute("id") *== 1).project(["name"]).asyncProperty{ $0.signal{ $0.oneString($1) } }

        // Create a r/w property that will be bound to the async property
        var lockCount = 0
        var unlockCount = 0
        let runloop = CFRunLoopGetCurrent()
        let group = dispatch_group_create()
        let changeHandler = ChangeHandler(
            onLock: {
                lockCount += 1
            },
            onUnlock: {
                unlockCount += 1
                dispatch_group_leave(group)
                CFRunLoopStop(runloop)
            }
        )
        
        var lhsValues: [String] = []
        var lhs: ReadWriteProperty<String>! = mutableValueProperty("initial lhs value", changeHandler, { newValue, _ in
            lhsValues.append(newValue)
        })

        // Verify the initial state
        XCTAssertEqual(lhs.value, "initial lhs value")
        XCTAssertEqual(lhsValues, [])
        XCTAssertEqual(lhs.signal.observerCount, 0)
        XCTAssertEqual(rhs.signal.observerCount, 1)
        XCTAssertEqual(lockCount, 0)
        XCTAssertEqual(unlockCount, 0)
        
        // Bind lhs property to the async rhs property, verify that rhs property's value is loaded asynchronously
        // and that lhs property's value is updated when the rhs value is ready
        dispatch_group_enter(group)
        _ = lhs <~ rhs
        XCTAssertEqual(lhs.value, "initial lhs value")
        XCTAssertEqual(lhsValues, [])
        XCTAssertEqual(lhs.signal.observerCount, 0)
        XCTAssertEqual(rhs.signal.observerCount, 2)
        XCTAssertEqual(lockCount, 1)
        XCTAssertEqual(unlockCount, 0)
        
        CFRunLoopRun()
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER)
        XCTAssertEqual(lhs.value, "")
        XCTAssertEqual(lhsValues, [""])
        XCTAssertEqual(lockCount, 1)
        XCTAssertEqual(unlockCount, 1)
        
        // TODO: Verify async updates to rhs relation/property
        
        // Nil out the lhs property and verify that the rhs property is unbound
        lhs = nil
        XCTAssertEqual(lhsValues, [""])
        XCTAssertEqual(rhs.signal.observerCount, 1)
        XCTAssertEqual(lockCount, 1)
        XCTAssertEqual(unlockCount, 1)
        
        // TODO: Change the rhs property's value and verify that lhs property's value is unaffected
    }
    
    func testBindBidiToAsyncReadWriteProperty() {
        // TODO
    }
}
