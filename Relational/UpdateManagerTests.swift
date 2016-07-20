//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import libRelational


class UpdateManagerTests: DBTestCase {
    func testAsyncUpdate() {
        let sqliteDB = makeDB().db.sqliteDatabase
        sqliteDB.getOrCreateRelation("n", scheme: ["n"]).ok!
        
        let db = TransactionalDatabase(sqliteDB)
        let r = db["n"]
        let u = r.union(r)
        
        TestAsyncObserver.assertChanges(u,
                                        change: {
                                            r.asyncAdd(["n": 1])
                                            r.asyncAdd(["n": 2])
                                            r.asyncAdd(["n": 3])
                                            r.asyncAdd(["n": 4]) },
                                        expectedAdded: [["n": 1], ["n": 2], ["n": 3], ["n": 4]],
                                        expectedRemoved: [])
        TestAsyncObserver.assertChanges(u,
                                        change: {
                                            r.asyncUpdate(Attribute("n") *== 2, newValues: ["n": 10])
                                            r.asyncDelete(Attribute("n") *== 3)
                                            r.asyncAdd(["n": 5]) },
                                        expectedAdded: [["n": 10], ["n": 5]],
                                        expectedRemoved: [["n": 2], ["n": 3]])
    }
    
    func testUpdateDuringAsyncUpdate() {
        let sqliteDB = makeDB().db.sqliteDatabase
        sqliteDB.getOrCreateRelation("n", scheme: ["n"]).ok!
        
        let db = TransactionalDatabase(sqliteDB)
        let r = db["n"]
        
        class TriggerRelation: Relation {
            var onUnderlyingRelationCallback: Void -> Void = {}
            
            var scheme: Scheme {
                return ["n"]
            }
            
            var underlyingRelationForQueryExecution: Relation {
                onUnderlyingRelationCallback()
                return MakeRelation(["n"], [1], [2], [3])
            }
            
            func contains(row: Row) -> Result<Bool, RelationError> {
                fatalError("unimplemented")
            }
            
            func update(query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
                fatalError("unimplemented")
            }
            
            func addChangeObserver(observer: RelationObserver, kinds: [RelationObservationKind]) -> (Void -> Void) {
                return {}
            }
        }
        
        let triggerRelation = TriggerRelation()
        triggerRelation.onUnderlyingRelationCallback = {
            dispatch_sync(dispatch_get_main_queue(), {
                UpdateManager.currentInstance.registerAdd(r, row: ["n": 2])
                UpdateManager.currentInstance.registerAdd(r, row: ["n": 5])
            })
            triggerRelation.onUnderlyingRelationCallback = {}
        }
        let intersection = r.intersection(triggerRelation)
        
        TestAsyncCoalescedObserver.assertChanges(intersection,
                                                 change: {
                                                    r.asyncAdd(["n": 1])
                                                    r.asyncAdd(["n": 4]) },
                                                 expectedAdded: [["n": 1], ["n": 2]],
                                                 expectedRemoved: [])
    }
    
    func testLimitedUpdateNotificationScope() {
        let sqliteDB = makeDB().db.sqliteDatabase
        sqliteDB.getOrCreateRelation("1", scheme: ["n"]).ok!
        sqliteDB.getOrCreateRelation("2", scheme: ["n"]).ok!
        
        let db = TransactionalDatabase(sqliteDB)
        let r1 = db["1"]
        let r2 = db["2"]
        
        let count1 = r1.count()
        let count2 = r2.count()
        
        TestAsyncObserver.assertNoChanges(to: count1,
                                          changingRelation: r2,
                                          change: { r2.asyncAdd(["n": 1]) })
        TestAsyncObserver.assertNoChanges(to: count2,
                                          changingRelation: r1,
                                          change: { r1.asyncAdd(["n": 1]) })
    }
    
    func testAsyncSnapshotRestore() {
        let sqliteDB = makeDB().db.sqliteDatabase
        sqliteDB.getOrCreateRelation("n", scheme: ["n"]).ok!
        
        let db = TransactionalDatabase(sqliteDB)
        let r = db["n"]
        
        r.add(["n": 1])
        r.add(["n": 2])
        
        let snapshot = db.takeSnapshot()
        
        r.delete(Attribute("n") *== 2)
        r.add(["n": 3])
        
        TestAsyncObserver.assertChanges(r,
                                        change: { db.asyncRestoreSnapshot(snapshot) },
                                        expectedAdded: [["n": 2]],
                                        expectedRemoved: [["n": 3]])
    }
    
    func testAsyncSnapshotRestoreWithOtherChanges() {
        let sqliteDB = makeDB().db.sqliteDatabase
        sqliteDB.getOrCreateRelation("n", scheme: ["n"]).ok!
        
        let db = TransactionalDatabase(sqliteDB)
        let r = db["n"]
        
        r.add(["n": 1])
        r.add(["n": 2])
        
        let snapshot = db.takeSnapshot()
        
        r.delete(Attribute("n") *== 2)
        r.add(["n": 3])
        
        TestAsyncCoalescedObserver.assertChanges(r,
                                                 change: {
                                                    r.asyncAdd(["n": 10])
                                                    db.asyncRestoreSnapshot(snapshot)
                                                    r.asyncAdd(["n": 11]) },
                                                 expectedAdded: [["n": 2], ["n": 11]],
                                                 expectedRemoved: [["n": 3]])
    }
    
    func testAsyncUpdateObservation() {
        let sqliteDB = makeDB().db.sqliteDatabase
        sqliteDB.getOrCreateRelation("n", scheme: ["n"]).ok!
        
        let db = TransactionalDatabase(sqliteDB)
        let r = db["n"]
        
        TestAsyncUpdateObserver.assertChanges(r,
                                              change: { r.asyncAdd(["n": 1]) },
                                              expectedContents: [["n": 1]])
        TestAsyncUpdateObserver.assertChanges(r,
                                              change: { r.asyncAdd(["n": 2]) },
                                              expectedContents: [["n": 1], ["n": 2]])
    }
    
    func testAsyncCoalescedUpdateObservation() {
        let sqliteDB = makeDB().db.sqliteDatabase
        sqliteDB.getOrCreateRelation("n", scheme: ["n"]).ok!
        
        let db = TransactionalDatabase(sqliteDB)
        let r = db["n"]
        
        TestAsyncCoalescedUpdateObserver.assertChanges(r,
                                                       change: { r.asyncAdd(["n": 1]) },
                                                       expectedContents: [["n": 1]])
        TestAsyncCoalescedUpdateObserver.assertChanges(r,
                                                       change: { r.asyncAdd(["n": 2]) },
                                                       expectedContents: [["n": 1], ["n": 2]])
    }
}

private class TestAsyncObserver: AsyncRelationChangeObserver {
    static func assertChanges(relation: Relation, change: Void -> Void, expectedAdded: Set<Row>, expectedRemoved: Set<Row>) {
        let observer = TestAsyncObserver()
        let remover = relation.addAsyncObserver(observer)
        change()
        CFRunLoopRun()
        XCTAssertEqual(observer.willChangeCount, 1)
        XCTAssertEqual(observer.didChangeCount, 1)
        XCTAssertEqual(observer.addedRows ?? [], expectedAdded)
        XCTAssertEqual(observer.removedRows ?? [], expectedRemoved)
        remover()
    }
    
    static func assertNoChanges(to to: Relation, changingRelation: Relation, change: Void -> Void) {
        let observer = TestAsyncObserver()
        let remover1 = to.addAsyncObserver(observer)
        let remover2 = changingRelation.addAsyncObserver(TestAsyncObserver()) // Just for the CFRunLoopStop it will do
        change()
        CFRunLoopRun()
        XCTAssertEqual(observer.willChangeCount, 0)
        XCTAssertEqual(observer.didChangeCount, 0)
        XCTAssertNil(observer.addedRows)
        XCTAssertNil(observer.removedRows)
        remover1()
        remover2()
    }
    
    var willChangeCount = 0
    var addedRows: Set<Row>?
    var removedRows: Set<Row>?
    var didChangeCount = 0
    
    func relationWillChange(relation: Relation) {
        willChangeCount += 1
    }
    
    func relationAddedRows(relation: Relation, rows: Set<Row>) {
        XCTAssertNil(addedRows)
        addedRows = rows
    }
    
    func relationRemovedRows(relation: Relation, rows: Set<Row>) {
        XCTAssertNil(removedRows)
        removedRows = rows
    }
    
    func relationDidChange(relation: Relation) {
        didChangeCount += 1
        CFRunLoopStop(CFRunLoopGetCurrent())
    }
}

private class TestAsyncCoalescedObserver: AsyncRelationChangeCoalescedObserver {
    static func assertChanges(relation: Relation, change: Void -> Void, expectedAdded: Set<Row>, expectedRemoved: Set<Row>) {
        let observer = TestAsyncCoalescedObserver()
        let remover = relation.addAsyncObserver(observer)
        change()
        CFRunLoopRun()
        XCTAssertEqual(observer.willChangeCount, 1)
        XCTAssertEqual(observer.addedRows ?? [], expectedAdded)
        XCTAssertEqual(observer.removedRows ?? [], expectedRemoved)
        remover()
    }
    
    var willChangeCount = 0
    var addedRows: Set<Row>?
    var removedRows: Set<Row>?
    
    func relationWillChange(relation: Relation) {
        willChangeCount += 1
    }
    
    func relationDidChange(relation: Relation, added: Set<Row>, removed: Set<Row>) {
        XCTAssertNil(addedRows)
        XCTAssertNil(removedRows)
        
        addedRows = added
        removedRows = removed
        
        CFRunLoopStop(CFRunLoopGetCurrent())
    }
}

private class TestAsyncUpdateObserver: AsyncRelationContentObserver {
    static func assertChanges(relation: Relation, change: Void -> Void, expectedContents: Set<Row>) {
        let observer = TestAsyncUpdateObserver()
        let remover = relation.addAsyncObserver(observer)
        change()
        CFRunLoopRun()
        XCTAssertEqual(observer.willChangeCount, 1)
        XCTAssertEqual(observer.rows, expectedContents)
        remover()
    }
    
    var willChangeCount = 0
    var rows: Set<Row> = []
    
    func relationWillChange(relation: Relation) {
        willChangeCount += 1
    }
    
    func relationNewContents(relation: Relation, rows: Set<Row>) {
        self.rows.unionInPlace(rows)
    }
    
    func relationDidChange(relation: Relation) {
        CFRunLoopStop(CFRunLoopGetCurrent())
    }
}

private class TestAsyncCoalescedUpdateObserver: AsyncRelationContentCoalescedObserver {
    static func assertChanges(relation: Relation, change: Void -> Void, expectedContents: Set<Row>) {
        let observer = TestAsyncCoalescedUpdateObserver()
        let remover = relation.addAsyncObserver(observer)
        change()
        CFRunLoopRun()
        XCTAssertEqual(observer.willChangeCount, 1)
        XCTAssertEqual(observer.rows, expectedContents)
        remover()
    }
    
    var willChangeCount = 0
    var rows: Set<Row> = []
    
    func relationWillChange(relation: Relation) {
        willChangeCount += 1
    }
    
    func relationDidChange(relation: Relation, rows: Set<Row>) {
        self.rows.unionInPlace(rows)
        CFRunLoopStop(CFRunLoopGetCurrent())
    }
}
