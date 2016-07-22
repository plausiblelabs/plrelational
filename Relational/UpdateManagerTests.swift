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
        
        TestAsyncChangeObserver.assertChanges(u,
                                        change: {
                                            r.asyncAdd(["n": 1])
                                            r.asyncAdd(["n": 2])
                                            r.asyncAdd(["n": 3])
                                            r.asyncAdd(["n": 4]) },
                                        expectedAdded: [["n": 1], ["n": 2], ["n": 3], ["n": 4]],
                                        expectedRemoved: [])
        TestAsyncChangeObserver.assertChanges(u,
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
            var onGetRowsCallback: Void -> Void = {}
            
            var scheme: Scheme {
                return ["n"]
            }
            
            var contentProvider: RelationContentProvider {
                return .Set({
                    self.onGetRowsCallback()
                    return [["n": 1], ["n": 2], ["n": 3]]
                })
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
        triggerRelation.onGetRowsCallback = {
            dispatch_sync(dispatch_get_main_queue(), {
                UpdateManager.currentInstance.registerAdd(r, row: ["n": 2])
                UpdateManager.currentInstance.registerAdd(r, row: ["n": 5])
            })
            triggerRelation.onGetRowsCallback = {}
        }
        let intersection = r.intersection(triggerRelation)
        
        TestAsyncChangeCoalescedObserver.assertChanges(intersection,
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
        
        TestAsyncChangeObserver.assertNoChanges(to: count1,
                                          changingRelation: r2,
                                          change: { r2.asyncAdd(["n": 1]) })
        TestAsyncChangeObserver.assertNoChanges(to: count2,
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
        
        TestAsyncChangeObserver.assertChanges(r,
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
        
        TestAsyncChangeCoalescedObserver.assertChanges(r,
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
        
        TestAsyncContentObserver.assertChanges(r,
                                              change: { r.asyncAdd(["n": 1]) },
                                              expectedContents: [["n": 1]])
        TestAsyncContentObserver.assertChanges(r,
                                              change: { r.asyncAdd(["n": 2]) },
                                              expectedContents: [["n": 1], ["n": 2]])
    }
    
    func testAsyncCoalescedUpdateObservation() {
        let sqliteDB = makeDB().db.sqliteDatabase
        sqliteDB.getOrCreateRelation("n", scheme: ["n"]).ok!
        
        let db = TransactionalDatabase(sqliteDB)
        let r = db["n"]
        
        TestAsyncContentCoalescedObserver.assertChanges(r,
                                                       change: { r.asyncAdd(["n": 1]) },
                                                       expectedContents: [["n": 1]])
        TestAsyncContentCoalescedObserver.assertChanges(r,
                                                       change: { r.asyncAdd(["n": 2]) },
                                                       expectedContents: [["n": 1], ["n": 2]])
    }
    
    func testErrorFromRelation() {
        let sqliteDB = makeDB().db.sqliteDatabase
        sqliteDB.getOrCreateRelation("n", scheme: ["n"]).ok!
        
        let db = TransactionalDatabase(sqliteDB)
        let r1 = db["n"]
        
        struct DummyError: ErrorType {}
        class ErroringRelation: Relation {
            var scheme: Scheme { return ["n"] }
            
            var contentProvider: RelationContentProvider {
                let results: [Result<Row, RelationError>] = [
                    .Ok(["n": 1]),
                    .Ok(["n": 2]),
                    .Ok(["n": 3]),
                    .Err(DummyError())
                ]
                return .Generator({ AnyGenerator(results.generate()) })
            }
            
            func contains(row: Row) -> Result<Bool, RelationError> {
                switch row["n"] {
                case 1, 2, 3 where row.values.count == 1: return .Ok(true)
                default: return .Ok(false)
                }
            }
            
            func update(query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
                fatalError("We don't do updates here")
            }
            
            func addChangeObserver(observer: RelationObserver, kinds: [RelationObservationKind]) -> (Void -> Void) {
                return {}
            }
        }
        
        let r2 = ErroringRelation()
        let union = r1.union(r2)
        
        let changeObserver = TestAsyncChangeObserver()
        let changeRemover = union.addAsyncObserver(changeObserver)
        let coalescedChangeObserver = TestAsyncChangeCoalescedObserver()
        let coalescedChangeRemover = union.addAsyncObserver(coalescedChangeObserver)
        let contentObserver = TestAsyncContentObserver()
        let contentRemover = union.addAsyncObserver(contentObserver)
        let contentCoalescedObserver = TestAsyncContentCoalescedObserver()
        let contentCoalescedRemover = union.addAsyncObserver(contentCoalescedObserver)
        
        r1.asyncAdd(["n": 4])
        r1.asyncAdd(["n": 5])
        
        CFRunLoopRun()
        
        changeRemover()
        coalescedChangeRemover()
        contentRemover()
        contentCoalescedRemover()
        
        XCTAssertTrue(changeObserver.error is DummyError)
        XCTAssertTrue(coalescedChangeObserver.result?.err is DummyError)
        XCTAssertTrue(contentObserver.error is DummyError)
        XCTAssertTrue(contentCoalescedObserver.result?.err is DummyError)
    }
}

private class TestAsyncChangeObserver: AsyncRelationChangeObserver {
    static func assertChanges(relation: Relation, change: Void -> Void, expectedAdded: Set<Row>, expectedRemoved: Set<Row>) {
        let observer = TestAsyncChangeObserver()
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
        let observer = TestAsyncChangeObserver()
        let remover1 = to.addAsyncObserver(observer)
        let remover2 = changingRelation.addAsyncObserver(TestAsyncChangeObserver()) // Just for the CFRunLoopStop it will do
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
    var error: RelationError?
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
    
    func relationError(relation: Relation, error: RelationError) {
        self.error = error
    }
    
    func relationDidChange(relation: Relation) {
        didChangeCount += 1
        CFRunLoopStop(CFRunLoopGetCurrent())
    }
}

private class TestAsyncChangeCoalescedObserver: AsyncRelationChangeCoalescedObserver {
    static func assertChanges(relation: Relation, change: Void -> Void, expectedAdded: Set<Row>, expectedRemoved: Set<Row>) {
        let observer = TestAsyncChangeCoalescedObserver()
        let remover = relation.addAsyncObserver(observer)
        change()
        CFRunLoopRun()
        XCTAssertEqual(observer.willChangeCount, 1)
        XCTAssertNil(observer.result?.err)
        XCTAssertEqual(observer.result?.ok?.added ?? [], expectedAdded)
        XCTAssertEqual(observer.result?.ok?.removed ?? [], expectedRemoved)
        remover()
    }
    
    var willChangeCount = 0
    var result: Result<NegativeSet<Row>, RelationError>?
    
    func relationWillChange(relation: Relation) {
        willChangeCount += 1
    }
    
    func relationDidChange(relation: Relation, result: Result<NegativeSet<Row>, RelationError>) {
        XCTAssertNil(self.result)
        self.result = result
        
        CFRunLoopStop(CFRunLoopGetCurrent())
    }
}

private class TestAsyncContentObserver: AsyncRelationContentObserver {
    static func assertChanges(relation: Relation, change: Void -> Void, expectedContents: Set<Row>) {
        let observer = TestAsyncContentObserver()
        let remover = relation.addAsyncObserver(observer)
        change()
        CFRunLoopRun()
        XCTAssertEqual(observer.willChangeCount, 1)
        XCTAssertEqual(observer.rows, expectedContents)
        remover()
    }
    
    var willChangeCount = 0
    var rows: Set<Row> = []
    var error: RelationError?
    
    func relationWillChange(relation: Relation) {
        willChangeCount += 1
    }
    
    func relationNewContents(relation: Relation, rows: Set<Row>) {
        self.rows.unionInPlace(rows)
    }
    
    func relationError(relation: Relation, error: RelationError) {
        self.error = error
    }
    
    func relationDidChange(relation: Relation) {
        CFRunLoopStop(CFRunLoopGetCurrent())
    }
}

private class TestAsyncContentCoalescedObserver: AsyncRelationContentCoalescedObserver {
    static func assertChanges(relation: Relation, change: Void -> Void, expectedContents: Set<Row>) {
        let observer = TestAsyncContentCoalescedObserver()
        let remover = relation.addAsyncObserver(observer)
        change()
        CFRunLoopRun()
        XCTAssertEqual(observer.willChangeCount, 1)
        XCTAssertEqual(observer.result?.ok, expectedContents)
        remover()
    }
    
    var willChangeCount = 0
    var result: Result<Set<Row>, RelationError>?
    
    func relationWillChange(relation: Relation) {
        willChangeCount += 1
    }
    
    func relationDidChange(relation: Relation, result: Result<Set<Row>, RelationError>) {
        self.result = result
        CFRunLoopStop(CFRunLoopGetCurrent())
    }
}
