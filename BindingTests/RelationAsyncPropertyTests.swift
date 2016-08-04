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

        func awaitCompletion(f: () -> Void) {
            f()
            CFRunLoopRun()
        }

        let nameRelation = r.select(Attribute("id") *== 1).project(["name"])
        let property = nameRelation.asyncProperty{ $0.signal{ $0.oneString($1) } }
        let removal = property.signal.observe(SignalObserver(
            valueWillChange: {
                willChangeCount += 1
            },
            valueChanging: { newValue, _ in
                changes.append(newValue)
            },
            valueDidChange: {
                didChangeCount += 1
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

        // Perform an async update to the underlying relation
        awaitCompletion{ r.asyncAdd(["id": 1, "name": "cat"]) }
        XCTAssertEqual(property.value, "cat")
        XCTAssertEqual(willChangeCount, 2)
        XCTAssertEqual(didChangeCount, 2)
        XCTAssertEqual(changes, ["", "cat"])
        
        // Perform another async update to the underlying relation (except this one isn't relevant to the
        // `select` that our signal is built on, so the signal shouldn't deliver a change)
        awaitCompletion{ r.asyncAdd(["id": 2, "name": "dog"]) }
        XCTAssertEqual(property.value, "cat")
        XCTAssertEqual(willChangeCount, 3)
        XCTAssertEqual(didChangeCount, 3)
        XCTAssertEqual(changes, ["", "cat"])

        // Perform an async delete-all-rows on the underlying relation
        awaitCompletion{ r.asyncDelete(true) }
        XCTAssertEqual(property.value, "")
        XCTAssertEqual(willChangeCount, 4)
        XCTAssertEqual(didChangeCount, 4)
        XCTAssertEqual(changes, ["", "cat", ""])
        
        removal()
    }
    
    func testAsyncReadWriteProperty() {
        let sqliteDB = makeDB().db
        let sqlr = sqliteDB.createRelation("animal", scheme: ["id", "name"]).ok!
        let db = TransactionalDatabase(sqliteDB)
        let r = db["animal"]
        
        var nameWillChangeCount = 0
        var nameDidChangeCount = 0
        var nameChanges: [String] = []
        
        let runloop = CFRunLoopGetCurrent()

        func updateName(newValue: String) {
            r.asyncUpdate(Attribute("id") *== 1, newValues: ["name": RelationValue(newValue)])
        }
        
        var nameSnapshotCount = 0
        var nameUpdateCount = 0
        var nameCommitCount = 0
        
        let nameConfig: RelationMutationConfig<String> = RelationMutationConfig(
            snapshot: {
                nameSnapshotCount += 1
                return db.takeSnapshot()
            },
            update: { newValue in
                nameUpdateCount += 1
                updateName(newValue)
            },
            commit: { _, newValue in
                nameCommitCount += 1
                updateName(newValue)
            }
        )
        
        // Create an async r/w property from the relation
        let nameRelation = r.select(Attribute("id") *== 1).project(["name"])
        let nameProperty = nameRelation.asyncProperty(nameConfig, { $0.signal{ $0.oneString($1) } })
        let nameObserverRemoval = nameProperty.signal.observe(SignalObserver(
            valueWillChange: {
                nameWillChangeCount += 1
            },
            valueChanging: { newValue, _ in
                nameChanges.append(newValue)
            },
            valueDidChange: {
                nameDidChangeCount += 1
                CFRunLoopStop(runloop)
            }
        ))

        // Create a r/w property that will be bound to the async property
        var lhsLockCount = 0
        var lhsUnlockCount = 0
        let lhsChangeHandler = ChangeHandler(
            onLock: {
                lhsLockCount += 1
            },
            onUnlock: {
                lhsUnlockCount += 1
                CFRunLoopStop(runloop)
            }
        )
        var lhsDidSetValues: [String] = []
        var lhsProperty: MutableValueProperty<String>! = mutableValueProperty("initial lhs value", lhsChangeHandler, { newValue, _ in
            lhsDidSetValues.append(newValue)
        })
        let lhsObserverRemoval = lhsProperty.signal.observe(SignalObserver(
            valueWillChange: {},
            valueChanging: { newValue, _ in
                //lhsChanges.append(newValue)
            },
            valueDidChange: {}
        ))

        // Verify that name property value remains nil until it is bound
        XCTAssertEqual(nameProperty.value, nil)
        XCTAssertEqual(nameWillChangeCount, 0)
        XCTAssertEqual(nameDidChangeCount, 0)
        XCTAssertEqual(nameChanges, [])
        XCTAssertEqual(nameSnapshotCount, 0)
        XCTAssertEqual(nameUpdateCount, 0)
        XCTAssertEqual(nameCommitCount, 0)

        // Verify the initial state of the lhs property
        XCTAssertEqual(lhsProperty.value, "initial lhs value")
        XCTAssertEqual(lhsDidSetValues, [])
        XCTAssertEqual(lhsLockCount, 0)
        XCTAssertEqual(lhsUnlockCount, 0)
        XCTAssertEqual(lhsProperty.signal.observerCount, 1)
        XCTAssertEqual(nameProperty.signal.observerCount, 2)

        // Bind lhs property to the async name property, verify that name property's value is loaded asynchronously
        // and that lhs property's value is updated when the rhs value is ready
        _ = lhsProperty <~> nameProperty
        XCTAssertEqual(nameProperty.value, nil)
        XCTAssertEqual(nameWillChangeCount, 1)
        XCTAssertEqual(nameDidChangeCount, 0)
        XCTAssertEqual(nameChanges, [])
        XCTAssertEqual(nameSnapshotCount, 0)
        XCTAssertEqual(nameUpdateCount, 0)
        XCTAssertEqual(nameCommitCount, 0)
        XCTAssertEqual(nameProperty.signal.observerCount, 3)
        XCTAssertEqual(lhsProperty.value, "initial lhs value")
        XCTAssertEqual(lhsDidSetValues, [])
        XCTAssertEqual(lhsLockCount, 1)
        XCTAssertEqual(lhsUnlockCount, 0)
        XCTAssertEqual(lhsProperty.signal.observerCount, 2)
        
        CFRunLoopRun()
        XCTAssertEqual(nameProperty.value, "")
        XCTAssertEqual(nameWillChangeCount, 1)
        XCTAssertEqual(nameDidChangeCount, 1)
        XCTAssertEqual(nameChanges, [""])
        XCTAssertEqual(nameSnapshotCount, 0)
        XCTAssertEqual(nameUpdateCount, 0)
        XCTAssertEqual(nameCommitCount, 0)
        XCTAssertEqual(lhsProperty.value, "")
        XCTAssertEqual(lhsDidSetValues, [""])
        XCTAssertEqual(lhsLockCount, 1)
        XCTAssertEqual(lhsUnlockCount, 1)

        // Update the underlying name relation and verify that changes are reflected in lhs property
        r.asyncAdd(["id": 1, "name": "cat"])
        XCTAssertEqual(nameProperty.value, "")
        XCTAssertEqual(nameWillChangeCount, 2)
        XCTAssertEqual(nameDidChangeCount, 1)
        XCTAssertEqual(nameChanges, [""])
        XCTAssertEqual(nameSnapshotCount, 0)
        XCTAssertEqual(nameUpdateCount, 0)
        XCTAssertEqual(nameCommitCount, 0)
        XCTAssertEqual(lhsProperty.value, "")
        XCTAssertEqual(lhsDidSetValues, [""])
        XCTAssertEqual(lhsLockCount, 2)
        XCTAssertEqual(lhsUnlockCount, 1)
        
        CFRunLoopRun()
        XCTAssertEqual(nameProperty.value, "cat")
        XCTAssertEqual(nameWillChangeCount, 2)
        XCTAssertEqual(nameDidChangeCount, 2)
        XCTAssertEqual(nameChanges, ["", "cat"])
        XCTAssertEqual(nameSnapshotCount, 0)
        XCTAssertEqual(nameUpdateCount, 0)
        XCTAssertEqual(nameCommitCount, 0)
        XCTAssertEqual(lhsProperty.value, "cat")
        XCTAssertEqual(lhsDidSetValues, ["", "cat"])
        XCTAssertEqual(lhsLockCount, 2)
        XCTAssertEqual(lhsUnlockCount, 2)
        
        // Update the lhs property value and verify that async property value is updated
        lhsProperty.change("lhs cat", transient: true)
        XCTAssertEqual(nameProperty.value, "cat")
        XCTAssertEqual(nameWillChangeCount, 3)
        XCTAssertEqual(nameDidChangeCount, 2)
        XCTAssertEqual(nameChanges, ["", "cat"])
        XCTAssertEqual(nameSnapshotCount, 1)
        XCTAssertEqual(nameUpdateCount, 1)
        XCTAssertEqual(nameCommitCount, 0)
        XCTAssertEqual(lhsProperty.value, "lhs cat")
        // Note: lhsValues isn't updated here because that only happens when didSet is invoked after
        // the bound name property has updated its value; not sure that really makes sense but that's
        // how it works for now
        XCTAssertEqual(lhsDidSetValues, ["", "cat"])
        // TODO: Not sure it makes sense to lock the lhs property (and its associated control) since it
        // was the one that initiated the change
        XCTAssertEqual(lhsLockCount, 3)
        XCTAssertEqual(lhsUnlockCount, 2)
        
        CFRunLoopRun()
        XCTAssertEqual(nameProperty.value, "lhs cat")
        XCTAssertEqual(nameWillChangeCount, 3)
        XCTAssertEqual(nameDidChangeCount, 3)
        XCTAssertEqual(nameChanges, ["", "cat", "lhs cat"])
        XCTAssertEqual(nameSnapshotCount, 1)
        XCTAssertEqual(nameUpdateCount, 1)
        XCTAssertEqual(nameCommitCount, 0)
        XCTAssertEqual(lhsProperty.value, "lhs cat")
        XCTAssertEqual(lhsDidSetValues, ["", "cat"])
        XCTAssertEqual(lhsLockCount, 3)
        XCTAssertEqual(lhsUnlockCount, 3)

        // TODO: Commit the lhs property value and verify that async property value is updated

        // Nil out the lhs property and verify that the async property is unbound
        lhsProperty = nil
        XCTAssertEqual(lhsDidSetValues, ["", "cat"])
        XCTAssertEqual(nameProperty.signal.observerCount, 2)
        XCTAssertEqual(lhsLockCount, 3)
        XCTAssertEqual(lhsUnlockCount, 3)

        nameObserverRemoval()
        lhsObserverRemoval()
    }
}
