//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import PLRelational
@testable import PLRelationalBinding

class RelationAsyncPropertyTests: BindingTestCase {
    
    func testAsyncReadOnlyProperty() {
        let sqliteDB = makeDB().db
        _ = sqliteDB.createRelation("animal", scheme: ["id", "name"]).ok!
        let db = TransactionalDatabase(sqliteDB)
        let r = db["animal"]

        let property = r
            .select(Attribute("id") *== 1)
            .project(["name"])
            .oneString()
            .property()
        
        let observer = StringObserver()

        func verify(value: String?, changes: [String], willChangeCount: Int, didChangeCount: Int, file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(property.value, value, file: file, line: line)
            XCTAssertEqual(observer.changes, changes, file: file, line: line)
            XCTAssertEqual(observer.willChangeCount, willChangeCount, file: file, line: line)
            XCTAssertEqual(observer.didChangeCount, didChangeCount, file: file, line: line)
        }
        
        // Verify that property value remains nil until we actually trigger the query by observing
        // the property's signal
        verify(value: nil, changes: [], willChangeCount: 0, didChangeCount: 0)

        // Observe the property's signal to trigger the async query
        let removal = observer.observe(property.signal)
        verify(value: nil, changes: [], willChangeCount: 1, didChangeCount: 0)
        awaitIdle()
        verify(value: "", changes: [""], willChangeCount: 1, didChangeCount: 1)

        // Perform an async update to the underlying relation
        r.asyncAdd(["id": 1, "name": "cat"])
        verify(value: "", changes: [""], willChangeCount: 2, didChangeCount: 1)
        awaitIdle()
        verify(value: "cat", changes: ["", "cat"], willChangeCount: 2, didChangeCount: 2)
        
        // Perform another async update to the underlying relation (except this one isn't relevant to the
        // `select` that our signal is built on, so the signal shouldn't deliver a change)
        r.asyncAdd(["id": 2, "name": "dog"])
        verify(value: "cat", changes: ["", "cat"], willChangeCount: 2, didChangeCount: 2)
        awaitIdle()
        verify(value: "cat", changes: ["", "cat"], willChangeCount: 2, didChangeCount: 2)

        // Perform an async delete-all-rows on the underlying relation
        r.asyncDelete(true)
        verify(value: "cat", changes: ["", "cat"], willChangeCount: 3, didChangeCount: 2)
        awaitIdle()
        verify(value: "", changes: ["", "cat", ""], willChangeCount: 3, didChangeCount: 3)
        
        removal()
    }
    
    func testAsyncReadOnlyPropertyWithInitialValue() {
        let sqliteDB = makeDB().db
        _ = sqliteDB.createRelation("animal", scheme: ["id", "name"]).ok!
        let db = TransactionalDatabase(sqliteDB)
        let r = db["animal"]
        
        let property = r
            .select(Attribute("id") *== 1)
            .project(["name"])
            .oneString(initialValue: "cow")
            .property()
        
        let observer = StringObserver()
        
        func verify(value: String?, changes: [String], willChangeCount: Int, didChangeCount: Int, file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(property.value, value, file: file, line: line)
            XCTAssertEqual(observer.changes, changes, file: file, line: line)
            XCTAssertEqual(observer.willChangeCount, willChangeCount, file: file, line: line)
            XCTAssertEqual(observer.didChangeCount, didChangeCount, file: file, line: line)
        }
        
        // Verify that property value remains nil until we actually observe the property's signal
        verify(value: nil, changes: [], willChangeCount: 0, didChangeCount: 0)
        
        // Observe the property's signal and verify that the initial value is delivered immediately
        let removal = observer.observe(property.signal)
        verify(value: "cow", changes: ["cow"], willChangeCount: 0, didChangeCount: 0)
        
        // Perform an async update to the underlying relation
        r.asyncAdd(["id": 1, "name": "cat"])
        verify(value: "cow", changes: ["cow"], willChangeCount: 1, didChangeCount: 0)
        awaitIdle()
        verify(value: "cat", changes: ["cow", "cat"], willChangeCount: 1, didChangeCount: 1)
        
        removal()
    }
    
    func testAsyncReadWriteProperty() {
        let sqliteDB = makeDB().db
        let sqlr = sqliteDB.createRelation("animal", scheme: ["id", "name"]).ok!
        let db = TransactionalDatabase(sqliteDB)
        let r = db["animal"]
        
        func updateName(_ newValue: String) {
            r.asyncUpdate(Attribute("id") *== 1, newValues: ["name": RelationValue(newValue)])
        }
        
        var nameSnapshotCount = 0
        var nameUpdateCount = 0
        var nameCommitCount = 0
        
        let nameMutator: RelationMutationConfig<String> = RelationMutationConfig(
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
        let nameProperty = r
            .select(Attribute("id") *== 1)
            .project(["name"])
            .oneString()
            .property(mutator: nameMutator)
        
        // Create a r/w property that will be bound (bidirectionally) to the async property
        var lhsLockCount = 0
        var lhsUnlockCount = 0
        let lhsChangeHandler = ChangeHandler(
            onLock: {
                lhsLockCount += 1
            },
            onUnlock: {
                lhsUnlockCount += 1
            }
        )
        var lhsDidSetValues: [String] = []
        var lhsProperty: MutableValueProperty<String>! = mutableValueProperty("initial lhs value", lhsChangeHandler, { newValue, _ in
            lhsDidSetValues.append(newValue)
        })

        let nameObserver = StringObserver()
        let lhsObserver = StringObserver()
        
        func verifyName(value: String?, changes: [String], willChangeCount: Int, didChangeCount: Int,
                        snapshotCount: Int, updateCount: Int, commitCount: Int,
                        file: StaticString = #file, line: UInt = #line)
        {
            XCTAssertEqual(nameProperty.value, value, file: file, line: line)
            XCTAssertEqual(nameObserver.changes, changes, file: file, line: line)
            XCTAssertEqual(nameObserver.willChangeCount, willChangeCount, "Incorrect willChangeCount", file: file, line: line)
            XCTAssertEqual(nameObserver.didChangeCount, didChangeCount, "Incorrect didChangeCount", file: file, line: line)
            XCTAssertEqual(nameSnapshotCount, snapshotCount, "Incorrect snapshotCount", file: file, line: line)
            XCTAssertEqual(nameUpdateCount, updateCount, "Incorrect updateCount", file: file, line: line)
            XCTAssertEqual(nameCommitCount, commitCount, "Incorrect commitCount", file: file, line: line)
        }

        func verifyLHS(value: String?, changes: [String],
                       didSetValues: [String], lockCount: Int, unlockCount: Int,
                       file: StaticString = #file, line: UInt = #line)
        {
            XCTAssertEqual(lhsProperty.value, value, file: file, line: line)
            XCTAssertEqual(lhsObserver.changes, changes, file: file, line: line)
            XCTAssertEqual(lhsDidSetValues, didSetValues, file: file, line: line)
            XCTAssertEqual(lhsLockCount, lockCount, "Incorrect lockCount", file: file, line: line)
            XCTAssertEqual(lhsUnlockCount, unlockCount, "Incorrect unlockCount", file: file, line: line)
        }
        
        func resetNameObserver() {
            nameObserver.reset()
            nameSnapshotCount = 0
            nameUpdateCount = 0
            nameCommitCount = 0
        }
        
        func resetLHSObserver() {
            lhsObserver.reset()
            lhsDidSetValues = []
            lhsLockCount = 0
            lhsUnlockCount = 0
        }
        
        // Verify that name property value remains nil until it is bound
        verifyName(value: nil, changes: [], willChangeCount: 0, didChangeCount: 0, snapshotCount: 0, updateCount: 0, commitCount: 0)

        // Verify the initial state of the lhs property
        verifyLHS(value: "initial lhs value", changes: [], didSetValues: [], lockCount: 0, unlockCount: 0)

        // Begin observing the properties
        let nameObserverRemoval = nameObserver.observe(nameProperty.signal)
        let lhsObserverRemoval = lhsObserver.observe(lhsProperty.signal)
        verifyName(value: nil, changes: [], willChangeCount: 1, didChangeCount: 0, snapshotCount: 0, updateCount: 0, commitCount: 0)
        verifyLHS(value: "initial lhs value", changes: ["initial lhs value"], didSetValues: [], lockCount: 0, unlockCount: 0)
        
        // Verify the initial observer count for lhsProperty and nameProperty (normally it would be 0, but we added our own
        // observer above, so we expect 1 here)
        XCTAssertEqual(lhsProperty.signal.observerCount, 1)
        XCTAssertEqual(nameProperty.signal.observerCount, 1)
        
        // Bidirectionally bind lhs property to the async name property
        _ = lhsProperty <~> nameProperty

        // Look at the observer counts to verify that lhsProperty has started observing nameProperty (note that nameProperty doesn't
        // start observing lhsProperty until the initial name value has been computed)
        XCTAssertEqual(lhsProperty.signal.observerCount, 1)
        XCTAssertEqual(nameProperty.signal.observerCount, 2)
        
        // Verify that name property's value is loaded asynchronously and that lhs property's value is
        // updated when the rhs value is ready
        verifyName(value: nil, changes: [], willChangeCount: 1, didChangeCount: 0, snapshotCount: 0, updateCount: 0, commitCount: 0)
        verifyLHS(value: "initial lhs value", changes: ["initial lhs value"], didSetValues: [], lockCount: 1, unlockCount: 0)
        awaitIdle()
        verifyName(value: "", changes: [""], willChangeCount: 1, didChangeCount: 1, snapshotCount: 0, updateCount: 0, commitCount: 0)
        verifyLHS(value: "", changes: ["initial lhs value", ""], didSetValues: [""], lockCount: 1, unlockCount: 1)
        resetNameObserver()
        resetLHSObserver()

        // Verify that nameProperty has started observing lhsProperty
        XCTAssertEqual(lhsProperty.signal.observerCount, 2)
        XCTAssertEqual(nameProperty.signal.observerCount, 2)

        // Update the underlying name relation and verify that changes are reflected in lhs property
        r.asyncAdd(["id": 1, "name": "cat"])
        verifyName(value: "", changes: [], willChangeCount: 1, didChangeCount: 0, snapshotCount: 0, updateCount: 0, commitCount: 0)
        verifyLHS(value: "", changes: [], didSetValues: [], lockCount: 1, unlockCount: 0)
        awaitIdle()
        verifyName(value: "cat", changes: ["cat"], willChangeCount: 1, didChangeCount: 1, snapshotCount: 0, updateCount: 0, commitCount: 0)
        verifyLHS(value: "cat", changes: ["cat"], didSetValues: ["cat"], lockCount: 1, unlockCount: 1)
        resetNameObserver()
        resetLHSObserver()

        // Update the lhs property value and verify that async property value is updated
        lhsProperty.change("lhs cat", transient: true)
        verifyName(value: "cat", changes: [], willChangeCount: 1, didChangeCount: 0, snapshotCount: 1, updateCount: 1, commitCount: 0)
        verifyLHS(value: "lhs cat", changes: ["lhs cat"], didSetValues: [], lockCount: 0, unlockCount: 0)
        awaitIdle()
        verifyName(value: "lhs cat", changes: ["lhs cat"], willChangeCount: 1, didChangeCount: 1, snapshotCount: 1, updateCount: 1, commitCount: 0)
        verifyLHS(value: "lhs cat", changes: ["lhs cat"], didSetValues: [], lockCount: 0, unlockCount: 0)
        resetNameObserver()
        resetLHSObserver()
        
        // Commit the lhs property value and verify that async property value is committed
        lhsProperty.change("lhs kat", transient: false)
        verifyName(value: "lhs cat", changes: [], willChangeCount: 1, didChangeCount: 0, snapshotCount: 0, updateCount: 0, commitCount: 1)
        verifyLHS(value: "lhs kat", changes: ["lhs kat"], didSetValues: [], lockCount: 0, unlockCount: 0)
        awaitIdle()
        verifyName(value: "lhs kat", changes: ["lhs kat"], willChangeCount: 1, didChangeCount: 1, snapshotCount: 0, updateCount: 0, commitCount: 1)
        verifyLHS(value: "lhs kat", changes: ["lhs kat"], didSetValues: [], lockCount: 0, unlockCount: 0)
        resetNameObserver()
        resetLHSObserver()

        // Nil out the lhs property and verify that the async property is unbound
        lhsProperty = nil
        XCTAssertEqual(nameProperty.signal.observerCount, 1)

        nameObserverRemoval()
        lhsObserverRemoval()

        XCTAssertEqual(nameProperty.signal.observerCount, 0)
    }
    
    func testAsyncFlatMap() {
        // TODO: Test case where underlying property's initial value is non-nil, but initial mapped property's
        // initial value is nil and the property is not yet started
    }
}
