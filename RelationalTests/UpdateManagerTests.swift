//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import libRelational


class UpdateManagerTests: DBTestCase {
    func testAsyncUpdate() {
        let sqliteDB = makeDB().db
        _ = sqliteDB.getOrCreateRelation("n", scheme: ["n"]).ok!
        
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
        let sqliteDB = makeDB().db
        _ = sqliteDB.getOrCreateRelation("n", scheme: ["n"]).ok!
        
        let db = TransactionalDatabase(sqliteDB)
        let r = db["n"]
        
        class TriggerRelation: Relation {
            var onGetRowsCallback: (Void) -> Void = {}
            
            var scheme: Scheme {
                return ["n"]
            }
            
            var contentProvider: RelationContentProvider {
                return .set({
                    self.onGetRowsCallback()
                    return [["n": 1], ["n": 2], ["n": 3]]
                })
            }
            
            func contains(_ row: Row) -> Result<Bool, RelationError> {
                fatalError("unimplemented")
            }
            
            func update(_ query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
                fatalError("unimplemented")
            }
            
            func addChangeObserver(_ observer: RelationObserver, kinds: [RelationObservationKind]) -> ((Void) -> Void) {
                return {}
            }
        }
        
        let triggerRelation = TriggerRelation()
        triggerRelation.onGetRowsCallback = {
            DispatchQueue.main.sync(execute: {
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
        let sqliteDB = makeDB().db
        _ = sqliteDB.getOrCreateRelation("1", scheme: ["n"]).ok!
        _ = sqliteDB.getOrCreateRelation("2", scheme: ["n"]).ok!
        
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
        let sqliteDB = makeDB().db
        _ = sqliteDB.getOrCreateRelation("n", scheme: ["n"]).ok!
        
        let db = TransactionalDatabase(sqliteDB)
        let r = db["n"]
        
        _ = r.add(["n": 1])
        _ = r.add(["n": 2])
        
        let snapshot = db.takeSnapshot()
        
        _ = r.delete(Attribute("n") *== 2)
        _ = r.add(["n": 3])
        
        TestAsyncChangeObserver.assertChanges(r,
                                        change: { db.asyncRestoreSnapshot(snapshot) },
                                        expectedAdded: [["n": 2]],
                                        expectedRemoved: [["n": 3]])
    }
    
    func testAsyncSnapshotRestoreWithOtherChanges() {
        let sqliteDB = makeDB().db
        _ = sqliteDB.getOrCreateRelation("n", scheme: ["n"]).ok!
        
        let db = TransactionalDatabase(sqliteDB)
        let r = db["n"]
        
        _ = r.add(["n": 1])
        _ = r.add(["n": 2])
        
        let snapshot = db.takeSnapshot()
        
        _ = r.delete(Attribute("n") *== 2)
        _ = r.add(["n": 3])
        
        TestAsyncChangeCoalescedObserver.assertChanges(r,
                                                 change: {
                                                    r.asyncAdd(["n": 10])
                                                    db.asyncRestoreSnapshot(snapshot)
                                                    r.asyncAdd(["n": 11]) },
                                                 expectedAdded: [["n": 2], ["n": 11]],
                                                 expectedRemoved: [["n": 3]])
    }
    
    func testAsyncUpdateObservation() {
        let sqliteDB = makeDB().db
        _ = sqliteDB.getOrCreateRelation("n", scheme: ["n"]).ok!
        
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
        let sqliteDB = makeDB().db
        _ = sqliteDB.getOrCreateRelation("n", scheme: ["n"]).ok!
        
        let db = TransactionalDatabase(sqliteDB)
        let r = db["n"]
        
        let observer = TestAsyncContentCoalescedObserver()
        let remover = r.addAsyncObserver(observer)
        observer.assertChanges({ r.asyncAdd(["n": 1]) },
                               expectedContents: [["n": 1]])
        observer.assertChanges({ r.asyncAdd(["n": 2]) },
                               expectedContents: [["n": 1], ["n": 2]])
        observer.assertChanges({ r.asyncDelete(true) },
                               expectedContents: [])
        remover()
    }
    
    func testAsyncCoalescedUpdateObservationWithSorting() {
        let sqliteDB = makeDB().db
        _ = sqliteDB.getOrCreateRelation("n", scheme: ["n"]).ok!
        
        let db = TransactionalDatabase(sqliteDB)
        let r = db["n"]
        
        let observer = TestAsyncContentCoalescedArrayObserver()
        let remover = r.addAsyncObserver(observer, postprocessor: sortByAttribute("n"))
        observer.assertChanges({ r.asyncAdd(["n": 1]) },
                               expectedContents: [["n": 1]])
        observer.assertChanges({ for i: Int64 in 2..<20 { r.asyncAdd(["n": .integer(i)]) } },
                               expectedContents: (1..<20).map({ ["n": .integer($0)] }))
        observer.assertChanges({ r.asyncDelete(true) },
                               expectedContents: [])
        remover()
    }
    
    func testErrorFromRelation() {
        let sqliteDB = makeDB().db
        _ = sqliteDB.getOrCreateRelation("n", scheme: ["n"]).ok!
        
        let db = TransactionalDatabase(sqliteDB)
        let r1 = db["n"]
        
        struct DummyError: Error {}
        class ErroringRelation: Relation {
            var scheme: Scheme { return ["n"] }
            
            var contentProvider: RelationContentProvider {
                let results: [Result<Row, RelationError>] = [
                    .Ok(["n": 1]),
                    .Ok(["n": 2]),
                    .Ok(["n": 3]),
                    .Err(DummyError())
                ]
                return .generator({ AnyIterator(results.makeIterator()) })
            }
            
            func contains(_ row: Row) -> Result<Bool, RelationError> {
                switch row["n"] {
                case 1 where row.count == 1, 2 where row.count == 1, 3 where row.count == 1: return .Ok(true)
                default: return .Ok(false)
                }
            }
            
            func update(_ query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
                fatalError("We don't do updates here")
            }
            
            func addChangeObserver(_ observer: RelationObserver, kinds: [RelationObservationKind]) -> ((Void) -> Void) {
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
        
        CFRunLoopRunOrFail()
        
        changeRemover()
        coalescedChangeRemover()
        contentRemover()
        contentCoalescedRemover()
        
        XCTAssertTrue(changeObserver.error is DummyError)
        XCTAssertTrue(coalescedChangeObserver.result?.err is DummyError)
        XCTAssertTrue(contentObserver.error is DummyError)
        XCTAssertTrue(contentCoalescedObserver.result?.err is DummyError)
    }
    
    func testMultipleCoalescedChangeObservations() {
        let sqliteDB = makeDB().db
        _ = sqliteDB.getOrCreateRelation("n", scheme: ["n"]).ok!
        
        let db = TransactionalDatabase(sqliteDB)
        let r = db["n"]
        
        let observer = TestAsyncChangeCoalescedObserver()
        let remover = r.addAsyncObserver(observer)
        
        r.asyncAdd(["n": 1])
        CFRunLoopRunOrFail()
        XCTAssertEqual(observer.willChangeCount, 1)
        XCTAssertNil(observer.result?.err)
        XCTAssertEqual(observer.result?.ok?.added, [["n": 1]])
        XCTAssertEqual(observer.result?.ok?.removed, [])
        observer.result = nil
        
        r.asyncAdd(["n": 2])
        CFRunLoopRunOrFail()
        XCTAssertEqual(observer.willChangeCount, 2)
        XCTAssertNil(observer.result?.err)
        XCTAssertEqual(observer.result?.ok?.added, [["n": 2]])
        XCTAssertEqual(observer.result?.ok?.removed, [])
        observer.result = nil
        
        r.asyncDelete(Attribute("n") *== 1)
        CFRunLoopRunOrFail()
        XCTAssertEqual(observer.willChangeCount, 3)
        XCTAssertNil(observer.result?.err)
        XCTAssertEqual(observer.result?.ok?.added, [])
        XCTAssertEqual(observer.result?.ok?.removed, [["n": 1]])
        observer.result = nil
        
        r.asyncDelete(Attribute("n") *== 2)
        CFRunLoopRunOrFail()
        XCTAssertEqual(observer.willChangeCount, 4)
        XCTAssertNil(observer.result?.err)
        XCTAssertEqual(observer.result?.ok?.added, [])
        XCTAssertEqual(observer.result?.ok?.removed, [["n": 2]])
        observer.result = nil
        
        remover()
    }
    
    func testMultipleCoalescedContentObservations() {
        let sqliteDB = makeDB().db
        _ = sqliteDB.getOrCreateRelation("n", scheme: ["n"]).ok!
        
        let db = TransactionalDatabase(sqliteDB)
        let r = db["n"]
        
        let observer = TestAsyncContentCoalescedObserver()
        let remover = r.addAsyncObserver(observer)
        
        r.asyncAdd(["n": 1])
        CFRunLoopRunOrFail()
        XCTAssertEqual(observer.willChangeCount, 1)
        XCTAssertNil(observer.result?.err)
        XCTAssertEqual(observer.result?.ok, [["n": 1]])
        observer.result = nil
        
        r.asyncAdd(["n": 2])
        CFRunLoopRunOrFail()
        XCTAssertEqual(observer.willChangeCount, 2)
        XCTAssertNil(observer.result?.err)
        XCTAssertEqual(observer.result?.ok, [["n": 1], ["n": 2]])
        observer.result = nil
        
        r.asyncDelete(Attribute("n") *== 1)
        CFRunLoopRunOrFail()
        XCTAssertEqual(observer.willChangeCount, 3)
        XCTAssertNil(observer.result?.err)
        XCTAssertEqual(observer.result?.ok, [["n": 2]])
        observer.result = nil
        
        r.asyncDelete(Attribute("n") *== 2)
        CFRunLoopRunOrFail()
        XCTAssertEqual(observer.willChangeCount, 4)
        XCTAssertNil(observer.result?.err)
        XCTAssertEqual(observer.result?.ok, [])
        observer.result = nil
        
        remover()
    }
    
    func testCoalescedContentObservationsWithJoin() {
        let sqliteDB = makeDB().db
        _ = sqliteDB.getOrCreateRelation("person", scheme: ["id", "name"]).ok!
        _ = sqliteDB.getOrCreateRelation("selected_person", scheme: ["id"]).ok!
        
        let db = TransactionalDatabase(sqliteDB)
        let persons = db["person"]
        let selectedPersonID = db["selected_person"]
        let selectedPerson = persons.join(selectedPersonID)
        let selectedPersonName = selectedPerson.project(["name"])
        let person1Name = persons.select(Attribute("id") *== 1).project(["name"])

        func addPerson(_ id: Int64, _ name: String) {
            let row: Row = [
                "id": RelationValue(id),
                "name": RelationValue(name)
            ]
            _ = persons.add(row)
        }
        
        addPerson(1, "Alice")
        addPerson(2, "Bob")
        
        let selectedPersonNameObserver = TestAsyncContentCoalescedObserver()
        let selectedPersonNameRemover = selectedPersonName.addAsyncObserver(selectedPersonNameObserver)
        let person1NameObserver = TestAsyncContentCoalescedObserver()
        let person1NameRemover = person1Name.addAsyncObserver(person1NameObserver)
        
        selectedPersonID.asyncAdd(["id": 1])
        CFRunLoopRun()
        XCTAssertEqual(selectedPersonNameObserver.result?.ok, [["name": "Alice"]])
        selectedPersonNameObserver.result = nil
        person1NameObserver.result = nil

        selectedPerson.asyncUpdate(true, newValues: ["name": "Alex"])
        CFRunLoopRun()
        XCTAssertEqual(person1NameObserver.result?.ok, [["name": "Alex"]])
        selectedPersonNameObserver.result = nil
        person1NameObserver.result = nil

        selectedPersonNameRemover()
        person1NameRemover()
    }
}

private class TestAsyncChangeObserver: AsyncRelationChangeObserver {
    static func assertChanges(_ relation: Relation, change: (Void) -> Void, expectedAdded: Set<Row>, expectedRemoved: Set<Row>, file: StaticString = #file, line: UInt = #line) {
        let observer = TestAsyncChangeObserver()
        let remover = relation.addAsyncObserver(observer)
        change()
        CFRunLoopRunOrFail(file: file, line: line)
        XCTAssertEqual(observer.willChangeCount, 1, file: file, line: line)
        XCTAssertEqual(observer.didChangeCount, 1, file: file, line: line)
        XCTAssertEqual(observer.addedRows ?? [], expectedAdded, file: file, line: line)
        XCTAssertEqual(observer.removedRows ?? [], expectedRemoved, file: file, line: line)
        remover()
    }
    
    static func assertNoChanges(to: Relation, changingRelation: Relation, file: StaticString = #file, line: UInt = #line, change: (Void) -> Void) {
        let observer = TestAsyncChangeObserver()
        let remover1 = to.addAsyncObserver(observer)
        let remover2 = changingRelation.addAsyncObserver(TestAsyncChangeObserver()) // Just for the CFRunLoopStop it will do
        change()
        CFRunLoopRunOrFail(file: file, line: line)
        XCTAssertEqual(observer.willChangeCount, 0, file: file, line: line)
        XCTAssertEqual(observer.didChangeCount, 0, file: file, line: line)
        XCTAssertNil(observer.addedRows, file: file, line: line)
        XCTAssertNil(observer.removedRows, file: file, line: line)
        remover1()
        remover2()
    }
    
    var willChangeCount = 0
    var addedRows: Set<Row>?
    var removedRows: Set<Row>?
    var error: RelationError?
    var didChangeCount = 0
    
    func relationWillChange(_ relation: Relation) {
        willChangeCount += 1
    }
    
    func relationAddedRows(_ relation: Relation, rows: Set<Row>) {
        XCTAssertNil(addedRows)
        addedRows = rows
    }
    
    func relationRemovedRows(_ relation: Relation, rows: Set<Row>) {
        XCTAssertNil(removedRows)
        removedRows = rows
    }
    
    func relationError(_ relation: Relation, error: RelationError) {
        self.error = error
    }
    
    func relationDidChange(_ relation: Relation) {
        didChangeCount += 1
        CFRunLoopStop(CFRunLoopGetCurrent())
    }
}

private class TestAsyncChangeCoalescedObserver: AsyncRelationChangeCoalescedObserver {
    static func assertChanges(_ relation: Relation, change: (Void) -> Void, expectedAdded: Set<Row>, expectedRemoved: Set<Row>, file: StaticString = #file, line: UInt = #line) {
        let observer = TestAsyncChangeCoalescedObserver()
        let remover = relation.addAsyncObserver(observer)
        change()
        CFRunLoopRunOrFail(file: file, line: line)
        XCTAssertEqual(observer.willChangeCount, 1, file: file, line: line)
        XCTAssertNil(observer.result?.err, file: file, line: line)
        XCTAssertEqual(observer.result?.ok?.added ?? [], expectedAdded, file: file, line: line)
        XCTAssertEqual(observer.result?.ok?.removed ?? [], expectedRemoved, file: file, line: line)
        remover()
    }
    
    var willChangeCount = 0
    var result: Result<NegativeSet<Row>, RelationError>?
    
    func relationWillChange(_ relation: Relation) {
        willChangeCount += 1
    }
    
    func relationDidChange(_ relation: Relation, result: Result<NegativeSet<Row>, RelationError>) {
        XCTAssertNil(self.result)
        self.result = result
        
        CFRunLoopStop(CFRunLoopGetCurrent())
    }
}

private class TestAsyncContentObserver: AsyncRelationContentObserver {
    static func assertChanges(_ relation: Relation, change: (Void) -> Void, expectedContents: Set<Row>, file: StaticString = #file, line: UInt = #line) {
        let observer = TestAsyncContentObserver()
        let remover = relation.addAsyncObserver(observer)
        change()
        CFRunLoopRunOrFail(file: file, line: line)
        XCTAssertEqual(observer.willChangeCount, 1, file: file, line: line)
        XCTAssertEqual(observer.rows, expectedContents, file: file, line: line)
        remover()
    }
    
    var willChangeCount = 0
    var rows: Set<Row> = []
    var error: RelationError?
    
    func relationWillChange(_ relation: Relation) {
        willChangeCount += 1
    }
    
    func relationNewContents(_ relation: Relation, rows: Set<Row>) {
        self.rows.formUnion(rows)
    }
    
    func relationError(_ relation: Relation, error: RelationError) {
        self.error = error
    }
    
    func relationDidChange(_ relation: Relation) {
        CFRunLoopStop(CFRunLoopGetCurrent())
    }
}

private class TestAsyncContentCoalescedObserver: AsyncRelationContentCoalescedObserver {
    static func assertChanges(_ relation: Relation, change: (Void) -> Void, expectedContents: Set<Row>) {
        let observer = TestAsyncContentCoalescedObserver()
        let remover = relation.addAsyncObserver(observer)
        observer.assertChanges(change, expectedContents: expectedContents)
        remover()
    }
    
    var willChangeCount = 0
    var result: Result<Set<Row>, RelationError>?
    
    func assertChanges(_ change: (Void) -> Void, expectedContents: Set<Row>, file: StaticString = #file, line: UInt = #line) {
        change()
        CFRunLoopRunOrFail(file: file, line: line)
        
        XCTAssertEqual(willChangeCount, 1, file: file, line: line)
        XCTAssertEqual(result?.ok, expectedContents, file: file, line: line)
        
        willChangeCount = 0
        result = nil
    }
    
    func relationWillChange(_ relation: Relation) {
        willChangeCount += 1
    }
    
    func relationDidChange(_ relation: Relation, result: Result<Set<Row>, RelationError>) {
        self.result = result
        CFRunLoopStop(CFRunLoopGetCurrent())
    }
}

private class TestAsyncContentCoalescedArrayObserver: AsyncRelationContentCoalescedObserver {
    static func assertChanges(_ relation: Relation, change: (Void) -> Void, postprocessor: @escaping (Set<Row>) -> [Row], expectedContents: [Row], file: StaticString = #file, line: UInt = #line) {
        let observer = TestAsyncContentCoalescedArrayObserver()
        let remover = relation.addAsyncObserver(observer, postprocessor: postprocessor)
        observer.assertChanges(change, expectedContents: expectedContents, file: file, line: line)
        remover()
    }
    
    var willChangeCount = 0
    var result: Result<[Row], RelationError>?
    
    func assertChanges(_ change: (Void) -> Void, expectedContents: [Row], file: StaticString = #file, line: UInt = #line) {
        change()
        CFRunLoopRunOrFail(file: file, line: line)
        
        XCTAssertEqual(willChangeCount, 1, file: file, line: line)
        XCTAssertNotNil(result?.ok, file: file, line: line)
        if let contents = result?.ok {
            XCTAssertEqual(contents, expectedContents, file: file, line: line)
        }
        
        willChangeCount = 0
        result = nil
    }
    
    func relationWillChange(_ relation: Relation) {
        willChangeCount += 1
    }
    
    func relationDidChange(_ relation: Relation, result: Result<[Row], RelationError>) {
        self.result = result
        CFRunLoopStop(CFRunLoopGetCurrent())
    }
}

/// Do a CFRunLoopRun, but with a timer so that if the runloop doesn't stop after ten seconds,
/// we kill it so tests don't get hung up forever.
func CFRunLoopRunOrFail(file: StaticString = #file, line: UInt = #line) {
    let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + 10, 0, 0, 0, { _ in
        XCTFail("CFRunLoopRun was not stopped by the tests, but it should have been", file: file, line: line)
        CFRunLoopStop(CFRunLoopGetCurrent())
    })
    CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, CFRunLoopMode.commonModes)
    CFRunLoopRun()
    CFRunLoopTimerInvalidate(timer)
}
