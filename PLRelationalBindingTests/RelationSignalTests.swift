//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import PLRelational
@testable import PLRelationalBinding

class RelationSignalTests: BindingTestCase {

    func testObservers() {
        let sqliteDB = makeDB().db
        _ = sqliteDB.createRelation("animal", scheme: ["id", "name"]).ok!
        let db = TransactionalDatabase(sqliteDB)
        let r = db["animal"]

        let signal = r
            .select(Attribute("id") *== 1)
            .project(["name"])
            .oneString()

        let observer1 = StringObserver()
        let observer2 = StringObserver()

        // Verify that the first observer gets a WillChange and triggers an async query
        let removal1 = observer1.observe(signal)
        verify(observer1, changes: [], willChangeCount: 1, didChangeCount: 0)
        verify(observer2, changes: [], willChangeCount: 0, didChangeCount: 0)

        // Verify that the second observer gets a WillChange (async query should already be initiated),
        // and that first observer does not get notified
        let removal2 = observer2.observe(signal)
        verify(observer1, changes: [], willChangeCount: 1, didChangeCount: 0)
        verify(observer2, changes: [], willChangeCount: 1, didChangeCount: 0)
        
        // Await async completion and verify state changes
        awaitIdle()
        verify(observer1, changes: [""], willChangeCount: 1, didChangeCount: 1)
        verify(observer2, changes: [""], willChangeCount: 1, didChangeCount: 1)

        // Perform an async update to the underlying relation
        r.asyncAdd(["id": 1, "name": "cat"])
        verify(observer1, changes: [""], willChangeCount: 2, didChangeCount: 1)
        verify(observer2, changes: [""], willChangeCount: 2, didChangeCount: 1)
        awaitIdle()
        verify(observer1, changes: ["", "cat"], willChangeCount: 2, didChangeCount: 2)
        verify(observer2, changes: ["", "cat"], willChangeCount: 2, didChangeCount: 2)

        // Perform another async update to the underlying relation (except this one isn't relevant to the
        // `select` that our signal is built on, so the signal shouldn't deliver a change)
        r.asyncAdd(["id": 2, "name": "dog"])
        verify(observer1, changes: ["", "cat"], willChangeCount: 2, didChangeCount: 2)
        verify(observer2, changes: ["", "cat"], willChangeCount: 2, didChangeCount: 2)
        awaitIdle()
        verify(observer1, changes: ["", "cat"], willChangeCount: 2, didChangeCount: 2)
        verify(observer2, changes: ["", "cat"], willChangeCount: 2, didChangeCount: 2)

        // Perform an async delete-all-rows on the underlying relation
        r.asyncDelete(true)
        verify(observer1, changes: ["", "cat"], willChangeCount: 3, didChangeCount: 2)
        verify(observer2, changes: ["", "cat"], willChangeCount: 3, didChangeCount: 2)
        
        // Add a third observer while the delete is pending and verify that it receives both a
        // WillChange and the latest value
        let observer3 = StringObserver()
        let removal3 = observer3.observe(signal)
        verify(observer3, changes: ["cat"], willChangeCount: 1, didChangeCount: 0)
        
        // Await async completion and verify state changes
        awaitIdle()
        verify(observer1, changes: ["", "cat", ""], willChangeCount: 3, didChangeCount: 3)
        verify(observer2, changes: ["", "cat", ""], willChangeCount: 3, didChangeCount: 3)
        verify(observer3, changes: ["cat", ""], willChangeCount: 1, didChangeCount: 1)
        
        removal1()
        removal2()
        removal3()
    }
    
    func testObserversWithExplicitInitialValue() {
        let sqliteDB = makeDB().db
        _ = sqliteDB.createRelation("animal", scheme: ["id", "name"]).ok!
        let db = TransactionalDatabase(sqliteDB)
        let r = db["animal"]
        
        let signal = r
            .select(Attribute("id") *== 1)
            .project(["name"])
            .oneString(initialValue: "foo")
        
        let observer1 = StringObserver()
        let observer2 = StringObserver()
        
        // Verify that the first observer gets the initial value
        let removal1 = observer1.observe(signal)
        verify(observer1, changes: ["foo"], willChangeCount: 0, didChangeCount: 0)
        verify(observer2, changes: [], willChangeCount: 0, didChangeCount: 0)
        
        // Verify that the second observer gets the initial value and that the first observer
        // does not get notified
        let removal2 = observer2.observe(signal)
        verify(observer1, changes: ["foo"], willChangeCount: 0, didChangeCount: 0)
        verify(observer2, changes: ["foo"], willChangeCount: 0, didChangeCount: 0)
        
        // Perform an async update to the underlying relation
        r.asyncAdd(["id": 1, "name": "cat"])
        verify(observer1, changes: ["foo"], willChangeCount: 1, didChangeCount: 0)
        verify(observer2, changes: ["foo"], willChangeCount: 1, didChangeCount: 0)
        awaitIdle()
        verify(observer1, changes: ["foo", "cat"], willChangeCount: 1, didChangeCount: 1)
        verify(observer2, changes: ["foo", "cat"], willChangeCount: 1, didChangeCount: 1)
        
        removal1()
        removal2()
    }
    
    func testSecondObserverWithValueAlreadyLoaded() {
        let sqliteDB = makeDB().db
        _ = sqliteDB.createRelation("animal", scheme: ["id", "name"]).ok!
        let db = TransactionalDatabase(sqliteDB)
        let r = db["animal"]
        
        let signal = r
            .select(Attribute("id") *== 1)
            .project(["name"])
            .oneString()
        
        let observer1 = StringObserver()
        let observer2 = StringObserver()
        
        // Verify that the first observer gets a WillChange and triggers an async query
        let removal1 = observer1.observe(signal)
        verify(observer1, changes: [], willChangeCount: 1, didChangeCount: 0)
        verify(observer2, changes: [], willChangeCount: 0, didChangeCount: 0)
        
        // Await async completion and verify state changes
        awaitIdle()
        verify(observer1, changes: [""], willChangeCount: 1, didChangeCount: 1)
        verify(observer2, changes: [], willChangeCount: 0, didChangeCount: 0)

        // Verify that the second observer gets the value that was already loaded and that the
        // first observer does not get notified
        let removal2 = observer2.observe(signal)
        verify(observer1, changes: [""], willChangeCount: 1, didChangeCount: 1)
        verify(observer2, changes: [""], willChangeCount: 0, didChangeCount: 0)
        
        // Perform an async update to the underlying relation
        r.asyncAdd(["id": 1, "name": "cat"])
        verify(observer1, changes: [""], willChangeCount: 2, didChangeCount: 1)
        verify(observer2, changes: [""], willChangeCount: 1, didChangeCount: 0)
        awaitIdle()
        verify(observer1, changes: ["", "cat"], willChangeCount: 2, didChangeCount: 2)
        verify(observer2, changes: ["", "cat"], willChangeCount: 1, didChangeCount: 1)
        
        removal1()
        removal2()
    }
    
    func testMap() {
        let sqliteDB = makeDB().db
        _ = sqliteDB.createRelation("animal", scheme: ["id", "name"]).ok!
        let db = TransactionalDatabase(sqliteDB)
        let r = db["animal"]
        
        let signal = r
            .select(Attribute("id") *== 1)
            .project(["name"])
            .oneString()
            .map{ "\($0)!" }
        
        let observer1 = StringObserver()
        let observer2 = StringObserver()
        
        // Verify that the first observer gets a WillChange and triggers an async query
        let removal1 = observer1.observe(signal)
        verify(observer1, changes: [], willChangeCount: 1, didChangeCount: 0)
        verify(observer2, changes: [], willChangeCount: 0, didChangeCount: 0)
        
        // Verify that the second observer gets a WillChange (async query should already be initiated),
        // and that first observer does not get notified
        let removal2 = observer2.observe(signal)
        verify(observer1, changes: [], willChangeCount: 1, didChangeCount: 0)
        verify(observer2, changes: [], willChangeCount: 1, didChangeCount: 0)
        
        // Await async completion and verify state changes
        awaitIdle()
        verify(observer1, changes: ["!"], willChangeCount: 1, didChangeCount: 1)
        verify(observer2, changes: ["!"], willChangeCount: 1, didChangeCount: 1)

        // Perform an async update to the underlying relation
        r.asyncAdd(["id": 1, "name": "cat"])
        verify(observer1, changes: ["!"], willChangeCount: 2, didChangeCount: 1)
        verify(observer2, changes: ["!"], willChangeCount: 2, didChangeCount: 1)
        awaitIdle()
        verify(observer1, changes: ["!", "cat!"], willChangeCount: 2, didChangeCount: 2)
        verify(observer2, changes: ["!", "cat!"], willChangeCount: 2, didChangeCount: 2)

        // Perform another async update to the underlying relation (except this one isn't relevant to the
        // `select` that our signal is built on, so the signal shouldn't deliver a change)
        r.asyncAdd(["id": 2, "name": "dog"])
        verify(observer1, changes: ["!", "cat!"], willChangeCount: 2, didChangeCount: 2)
        verify(observer2, changes: ["!", "cat!"], willChangeCount: 2, didChangeCount: 2)
        awaitIdle()
        verify(observer1, changes: ["!", "cat!"], willChangeCount: 2, didChangeCount: 2)
        verify(observer2, changes: ["!", "cat!"], willChangeCount: 2, didChangeCount: 2)
        
        // Perform an async delete-all-rows on the underlying relation
        r.asyncDelete(true)
        verify(observer1, changes: ["!", "cat!"], willChangeCount: 3, didChangeCount: 2)
        verify(observer2, changes: ["!", "cat!"], willChangeCount: 3, didChangeCount: 2)
        awaitIdle()
        verify(observer1, changes: ["!", "cat!", "!"], willChangeCount: 3, didChangeCount: 3)
        verify(observer2, changes: ["!", "cat!", "!"], willChangeCount: 3, didChangeCount: 3)
        
        removal1()
        removal2()
    }
    
    func testRemoval() {
        let sqliteDB = makeDB().db
        _ = sqliteDB.createRelation("animal", scheme: ["id", "name"]).ok!
        let db = TransactionalDatabase(sqliteDB)
        let r = db["animal"]
        
        let signal = r
            .select(Attribute("id") *== 1)
            .project(["name"])
            .oneString()
        
        let observer1 = StringObserver()
        let observer2 = StringObserver()
        
        // Verify that the first observer gets a WillChange and triggers an async query
        let removal1 = observer1.observe(signal)
        verify(observer1, changes: [], willChangeCount: 1, didChangeCount: 0)
        verify(observer2, changes: [], willChangeCount: 0, didChangeCount: 0)
        
        // Verify that the second observer gets a WillChange (async query should already be initiated),
        // and that first observer does not get notified
        let removal2 = observer2.observe(signal)
        verify(observer1, changes: [], willChangeCount: 1, didChangeCount: 0)
        verify(observer2, changes: [], willChangeCount: 1, didChangeCount: 0)
        
        // Remove the first observer before the async query completes
        removal1()
        
        // Await async completion and verify state changes
        awaitIdle()
        verify(observer1, changes: [], willChangeCount: 1, didChangeCount: 0)
        verify(observer2, changes: [""], willChangeCount: 1, didChangeCount: 1)
        
        // Perform an async update to the underlying relation
        r.asyncAdd(["id": 1, "name": "cat"])
        verify(observer1, changes: [], willChangeCount: 1, didChangeCount: 0)
        verify(observer2, changes: [""], willChangeCount: 2, didChangeCount: 1)

        // Remove the second observer before the async update completes
        removal2()

        // Await async completion and verify state changes
        awaitIdle()
        verify(observer1, changes: [], willChangeCount: 1, didChangeCount: 0)
        verify(observer2, changes: [""], willChangeCount: 2, didChangeCount: 1)
    }
}
