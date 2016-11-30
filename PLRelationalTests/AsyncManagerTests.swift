//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import PLRelational


class AsyncManagerTests: DBTestCase {
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
                AsyncManager.currentInstance.registerAdd(r, row: ["n": 2])
                AsyncManager.currentInstance.registerAdd(r, row: ["n": 5])
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
    
    func testAsyncMultipleUpdateObservation() {
        let sqliteDB = makeDB().db
        _ = sqliteDB.getOrCreateRelation("n", scheme: ["n", "m"]).ok!
        
        let db = TransactionalDatabase(sqliteDB)
        let r = db["n"]
        
        TestAsyncContentObserver.assertChanges(r,
                                               change: { r.asyncAdd(["n": 1, "m": 0]) },
                                               expectedContents: [["n": 1, "m": 0]])
        TestAsyncChangeCoalescedObserver.assertChanges(
            r,
            change: {
                r.asyncUpdate(true, newValues: ["n": 2])
                r.asyncUpdate(true, newValues: ["n": 3])
                r.asyncUpdate(true, newValues: ["n": 4])
                r.asyncUpdate(true, newValues: ["n": 5])
            },
            expectedAdded: [["n": 5, "m": 0]],
            expectedRemoved: [["n": 1, "m": 0]])
    }
    
    func testAsyncUpdateObservationWithComplexRelation() {
        let sqliteDB = makeDB().db
        _ = sqliteDB.getOrCreateRelation("object", scheme: ["obj_id", "name"]).ok!
        _ = sqliteDB.getOrCreateRelation("tab", scheme: ["tab_id", "current_item_id"]).ok!
        _ = sqliteDB.getOrCreateRelation("history_item", scheme: ["item_id", "tab_id", "obj_id", "position"]).ok!
        
        let db = TransactionalDatabase(sqliteDB)
        let objects = db["object"]
        let historyItems = db["history_item"]
        let tabs = db["tab"]

        let tabHistoryItems = historyItems
            .renameAttributes(["item_id": "current_item_id"])
        
        let currentHistoryItemForEachTab = tabs
            .leftOuterJoin(tabHistoryItems)
        
        let tabObjects = currentHistoryItemForEachTab
            .project(["tab_id", "obj_id"])
            .leftOuterJoin(objects)

        TestAsyncContentObserver.assertChanges(
            objects,
            change: {
                objects.asyncAdd(["obj_id": "o1", "name": "Object1"])
                objects.asyncAdd(["obj_id": "o2", "name": "Object2"])
                objects.asyncAdd(["obj_id": "o3", "name": "Object3"])
            },
            expectedContents: [
                ["obj_id": "o1", "name": "Object1"],
                ["obj_id": "o2", "name": "Object2"],
                ["obj_id": "o3", "name": "Object3"]
            ]
        )
        
        TestAsyncContentObserver.assertChanges(
            tabs,
            change: {
                tabs.asyncAdd(["tab_id": "t1", "current_item_id": "i1"])
                tabs.asyncAdd(["tab_id": "t2", "current_item_id": "i2"])
            },
            expectedContents: [
                ["tab_id": "t1", "current_item_id": "i1"],
                ["tab_id": "t2", "current_item_id": "i2"]
            ]
        )

        TestAsyncContentObserver.assertChanges(
            historyItems,
            change: {
                historyItems.asyncAdd(["item_id": "i1", "tab_id": "t1", "obj_id": "o1", "position": 1])
                historyItems.asyncAdd(["item_id": "i2", "tab_id": "t2", "obj_id": "o2", "position": 1])
                historyItems.asyncAdd(["item_id": "i3", "tab_id": "t2", "obj_id": "o3", "position": 2])
            },
            expectedContents: [
                ["item_id": "i1", "tab_id": "t1", "obj_id": "o1", "position": 1],
                ["item_id": "i2", "tab_id": "t2", "obj_id": "o2", "position": 1],
                ["item_id": "i3", "tab_id": "t2", "obj_id": "o3", "position": 2],
            ]
        )

        AssertEqual(
            tabObjects,
            MakeRelation(
                ["tab_id", "obj_id", "name"],
                ["t1", "o1", "Object1"],
                ["t2", "o2", "Object2"]
            )
        )
        
        func deleteObject(_ objID: String) {
            let group = DispatchGroup()
            group.enter()

            objects.cascadingDelete(
                Attribute("obj_id") *== RelationValue(objID),
                cascade: { (relation, row) in
                    if relation === objects {
                        let rowObjID = row["obj_id"]
                        return [
                            (historyItems, Attribute("obj_id") *== rowObjID)
                        ]
                    } else {
                        return []
                    }
                },
                update: { (relation, row) in
                    if relation === historyItems {
                        // XXX: This is hardcoded to set the new current item for the second tab
                        return [
                            CascadingUpdate(
                                relation: tabs,
                                query: Attribute("tab_id") *== "t2",
                                attributes: ["current_item_id"],
                                fromRelation: MakeRelation(["current_item_id"], ["i3"])
                            )
                        ]
                    } else {
                        return []
                    }
                },
                completionCallback: { _ in
                    group.leave()
                }
            )
            
            let runloop = CFRunLoopGetCurrent()!
            group.notify(queue: DispatchQueue.global(), execute: { runloop.async({ CFRunLoopStop(runloop) }) })
            CFRunLoopRun()
        }
        
        TestAsyncChangeCoalescedObserver.assertChanges(
            tabObjects,
            change: {
                deleteObject("o2")
            },
            expectedAdded: [
                ["tab_id": "t2", "obj_id": "o3", "name": "Object3"]
            ],
            expectedRemoved: [
                ["tab_id": "t2", "obj_id": "o2", "name": "Object2"]
            ]
        )
        
        AssertEqual(
            tabObjects,
            MakeRelation(
                ["tab_id", "obj_id", "name"],
                ["t1", "o1", "Object1"],
                ["t2", "o3", "Object3"]
            )
        )
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
    
    func testStateObservation() {
        let sqliteDB = makeDB().db
        _ = sqliteDB.getOrCreateRelation("n", scheme: ["n"]).ok!
        
        let db = TransactionalDatabase(sqliteDB)
        let r = db["n"]
        
        let observer = TestAsyncContentCoalescedObserver()
        let remover = r.addAsyncObserver(observer, postprocessor: {
            XCTAssertEqual(AsyncManager.currentInstance.state, .stopping)
            return $0
        })
        
        var observedStates: [AsyncManager.State] = [AsyncManager.currentInstance.state]
        let stateObserverRemover = AsyncManager.currentInstance.addStateObserver({
            observedStates.append($0)
        })
        
        XCTAssertEqual(AsyncManager.currentInstance.state, .idle)
        
        r.asyncAdd(["n": 1])
        XCTAssertEqual(AsyncManager.currentInstance.state, .pending)
        
        CFRunLoopRunOrFail()
        
        XCTAssertEqual(AsyncManager.currentInstance.state, .idle)
        remover()
        stateObserverRemover()
        
        XCTAssertEqual(observedStates, [.idle, .pending, .running, .stopping, .idle])
    }
    
    func testStatesWithQuery() {
        let r = MakeRelation(["n"], [1], [2], [3])
        
        let runloop = CFRunLoopGetCurrent()!
        let manager = AsyncManager.currentInstance
        
        XCTAssertEqual(manager.state, .idle)
        
        let remover = manager.addStateObserver({ _ in CFRunLoopStop(runloop) })
        
        var didRun = false
        r.asyncAllRows({ result in
            XCTAssertEqual(manager.state, .running)
            
            XCTAssertNotNil(result.ok)
            XCTAssertNil(result.err)
            XCTAssertEqual(result.ok, [["n": 1], ["n": 2], ["n": 3]])
            CFRunLoopStop(runloop)
            didRun = true
        })
        XCTAssertEqual(manager.state, .pending)
        
        let start = ProcessInfo.processInfo.systemUptime
        while manager.state != .idle && ProcessInfo.processInfo.systemUptime - start < 10 {
            CFRunLoopRunOrFail()
        }
        XCTAssertTrue(didRun)
        XCTAssertEqual(manager.state, .idle)
        
        remover()
    }
    
    func testQueryInDidChangeCallback() {
        let r = MakeRelation(["n"])
        
        class Observer: AsyncRelationChangeObserver {
            func relationWillChange(_ relation: Relation) {}
            func relationAddedRows(_ relation: Relation, rows: Set<Row>) {}
            func relationRemovedRows(_ relation: Relation, rows: Set<Row>) {}
            
            func relationError(_ relation: Relation, error: RelationError) {
                XCTFail("Got unexpected error \(error)")
            }
            
            func relationDidChange(_ relation: Relation) {
                relation.asyncAllRows({ result in
                    XCTAssertNil(result.err)
                    XCTAssertEqual(result.ok, [["n": 1]])
                    CFRunLoopStop(CFRunLoopGetCurrent())
                })
            }
        }
        
        let remover = r.addAsyncObserver(Observer())
        
        r.asyncAdd(["n": 1])
        CFRunLoopRunOrFail()
        
        remover()
        
        while AsyncManager.currentInstance.state != .idle {
            let remover = AsyncManager.currentInstance.addStateObserver({ _ in CFRunLoopStop(CFRunLoopGetCurrent()) })
            CFRunLoopRunOrFail()
            remover()
        }
    }
    
    func testDeleteNotificationsWithSelect() {
        let sqliteDB = makeDB().db
        XCTAssertNil(sqliteDB.getOrCreateRelation("person", scheme: ["id", "name"]).err)
        
        let db = TransactionalDatabase(sqliteDB)
        let r = db["person"]
        
        XCTAssertNil(r.add(["id": 1, "name": "Alf"]).err)
        XCTAssertNil(r.add(["id": 2, "name": "Tina"]).err)
        XCTAssertNil(r.add(["id": 3, "name": "Tony"]).err)
        XCTAssertNil(r.add(["id": 4, "name": "Mr. T"]).err)
        
        let rObserver = TestAsyncChangeObserver()
        let rRemover = r.addAsyncObserver(rObserver)
        
        let oneName = r.select(Attribute("id") *== 4).project(["name"])
        
        let oneNameObserver = TestAsyncChangeObserver()
        let oneNameRemover = oneName.addAsyncObserver(oneNameObserver)
        
        r.asyncDelete(Attribute("id") *== 2)
        CFRunLoopRunOrFail()
        
        XCTAssertEqual(rObserver.willChangeCount, 1)
        XCTAssertEqual(rObserver.addedRows ?? [], [])
        XCTAssertEqual(rObserver.removedRows, [["id": 2, "name": "Tina"]])
        XCTAssertNil(rObserver.error)
        XCTAssertEqual(rObserver.didChangeCount, 1)
        
        XCTAssertEqual(oneNameObserver.willChangeCount, 0)
        XCTAssertEqual(oneNameObserver.addedRows ?? [], [])
        XCTAssertEqual(oneNameObserver.removedRows ?? [], [])
        XCTAssertNil(oneNameObserver.error)
        XCTAssertEqual(oneNameObserver.didChangeCount, 0)
        
        rObserver.willChangeCount = 0
        rObserver.addedRows = nil
        rObserver.removedRows = nil
        rObserver.error = nil
        rObserver.didChangeCount = 0
        
        oneNameObserver.willChangeCount = 0
        oneNameObserver.addedRows = nil
        oneNameObserver.removedRows = nil
        oneNameObserver.error = nil
        oneNameObserver.didChangeCount = 0
        
        r.asyncDelete(Attribute("id") *== 4)
        CFRunLoopRunOrFail()
        
        XCTAssertEqual(rObserver.willChangeCount, 1)
        XCTAssertEqual(rObserver.addedRows ?? [], [])
        XCTAssertEqual(rObserver.removedRows, [["id": 4, "name": "Mr. T"]])
        XCTAssertNil(rObserver.error)
        XCTAssertEqual(rObserver.didChangeCount, 1)
        
        XCTAssertEqual(oneNameObserver.willChangeCount, 1)
        XCTAssertEqual(oneNameObserver.addedRows ?? [], [])
        XCTAssertEqual(oneNameObserver.removedRows, [["name": "Mr. T"]])
        XCTAssertNil(oneNameObserver.error)
        XCTAssertEqual(oneNameObserver.didChangeCount, 1)
        
        rRemover()
        oneNameRemover()
    }
    
    func testCaching() {
        let sqliteDB = makeDB().db
        XCTAssertNil(sqliteDB.getOrCreateRelation("person", scheme: ["id", "name"]).err)
        
        let db = TransactionalDatabase(sqliteDB)
        let r = db["person"]
        
        let cachingR = CachingRelation(r, limit: 2)
        
        let derived = cachingR.project(["name"])
        let observer = TestAsyncContentCoalescedObserver()
        let remover = derived.addAsyncObserver(observer)
        
        r.asyncAdd(["id": 1, "name": "Susan"])
        
        CFRunLoopRunOrFail()
        
        XCTAssertEqual(observer.willChangeCount, 1)
        XCTAssertEqual(observer.result?.ok, [["name": "Susan"]])
        XCTAssertEqual(cachingR.cache, [["id": 1, "name": "Susan"]])
        
        r.asyncAdd(["id": 2, "name": "Jane"])
        
        CFRunLoopRunOrFail()
        
        XCTAssertEqual(observer.willChangeCount, 2)
        XCTAssertEqual(observer.result?.ok, [["name": "Susan"], ["name": "Jane"]])
        XCTAssertEqual(cachingR.cache, [["id": 1, "name": "Susan"], ["id": 2, "name": "Jane"]])
        
        r.asyncAdd(["id": 3, "name": "Alice"])
        
        CFRunLoopRunOrFail()
        
        XCTAssertEqual(observer.willChangeCount, 3)
        XCTAssertEqual(observer.result?.ok, [["name": "Susan"], ["name": "Jane"], ["name": "Alice"]])
        XCTAssertNil(cachingR.cache)
        
        remover()
    }
    
    func testUpdateNotificationsWithCachingJoin() {
        let sqliteDB = makeDB().db
        XCTAssertNil(sqliteDB.getOrCreateRelation("person", scheme: ["id", "name"]).err)
        XCTAssertNil(sqliteDB.getOrCreateRelation("selected", scheme: ["id"]).err)
        
        let db = TransactionalDatabase(sqliteDB)
        let person = db["person"]
        let selected = db["selected"]
        
        XCTAssertNil(selected.add(["id": 1]).err)
        
        XCTAssertNil(person.add(["id": 1, "name": "Alf"]).err)
        XCTAssertNil(person.add(["id": 2, "name": "Tina"]).err)
        XCTAssertNil(person.add(["id": 3, "name": "Tony"]).err)
        XCTAssertNil(person.add(["id": 4, "name": "Mr. T"]).err)
        
        let selectedName = person.join(CachingRelation(selected, limit: 2))
        
        let personObserver = TestAsyncChangeObserver()
        let personRemover = person.addAsyncObserver(personObserver)
        
        let selectedObserver = TestAsyncChangeObserver()
        let selectedRemover = selected.addAsyncObserver(selectedObserver)
        
        let oneName = person.select(Attribute("id") *== 4).project(["name"])
        
        let oneNameObserver = TestAsyncChangeObserver()
        let oneNameRemover = oneName.addAsyncObserver(oneNameObserver)
        
        func reset() {
            func reset(_ observer: TestAsyncChangeObserver) {
                observer.willChangeCount = 0
                observer.addedRows = nil
                observer.removedRows = nil
                observer.error = nil
                observer.didChangeCount = 0
            }
            
            reset(personObserver)
            reset(oneNameObserver)
            reset(selectedObserver)
        }
        
        selectedName.asyncUpdate(true, newValues: ["name": "Alfonzo"])
        CFRunLoopRunOrFail()
        
        reset()
        
        selectedName.asyncUpdate(true, newValues: ["name": "Alfred"])
        CFRunLoopRunOrFail()
        
        XCTAssertEqual(personObserver.willChangeCount, 1)
        XCTAssertEqual(personObserver.addedRows, [["id": 1, "name": "Alfred"]])
        XCTAssertEqual(personObserver.removedRows, [["id": 1, "name": "Alfonzo"]])
        XCTAssertNil(personObserver.error)
        XCTAssertEqual(personObserver.didChangeCount, 1)
        
        XCTAssertEqual(oneNameObserver.willChangeCount, 0)
        XCTAssertEqual(oneNameObserver.addedRows ?? [], [])
        XCTAssertEqual(oneNameObserver.removedRows ?? [], [])
        XCTAssertNil(oneNameObserver.error)
        XCTAssertEqual(oneNameObserver.didChangeCount, 0)
        
        reset()
        
        selected.asyncAdd(["id": 2])
        CFRunLoopRunOrFail()
        
        reset()
        
        selectedName.asyncUpdate(true, newValues: ["name": "Common"])
        CFRunLoopRunOrFail()
        
        XCTAssertEqual(personObserver.willChangeCount, 1)
        XCTAssertEqual(personObserver.addedRows, [["id": 1, "name": "Common"], ["id": 2, "name": "Common"]])
        XCTAssertEqual(personObserver.removedRows, [["id": 1, "name": "Alfred"], ["id": 2, "name": "Tina"]])
        XCTAssertNil(personObserver.error)
        XCTAssertEqual(personObserver.didChangeCount, 1)
        
        XCTAssertEqual(oneNameObserver.willChangeCount, 0)
        XCTAssertEqual(oneNameObserver.addedRows ?? [], [])
        XCTAssertEqual(oneNameObserver.removedRows ?? [], [])
        XCTAssertNil(oneNameObserver.error)
        XCTAssertEqual(oneNameObserver.didChangeCount, 0)
        
        reset()
        
        selected.asyncUpdate(true, newValues: ["id": 4])
        CFRunLoopRunOrFail()
        
        reset()
        
        selectedName.asyncUpdate(true, newValues: ["name": "Mr. Trombone"])
        CFRunLoopRunOrFail()
        
        XCTAssertEqual(personObserver.willChangeCount, 1)
        XCTAssertEqual(personObserver.addedRows, [["id": 4, "name": "Mr. Trombone"]])
        XCTAssertEqual(personObserver.removedRows, [["id": 4, "name": "Mr. T"]])
        XCTAssertNil(personObserver.error)
        XCTAssertEqual(personObserver.didChangeCount, 1)
        
        XCTAssertEqual(oneNameObserver.willChangeCount, 1)
        XCTAssertEqual(oneNameObserver.addedRows, [["name": "Mr. Trombone"]])
        XCTAssertEqual(oneNameObserver.removedRows, [["name": "Mr. T"]])
        XCTAssertNil(oneNameObserver.error)
        XCTAssertEqual(oneNameObserver.didChangeCount, 1)
        
        personRemover()
        selectedRemover()
        oneNameRemover()
    }
    
    func testUpdateNotificationsWithMemoryTableJoin() {
        let sqliteDB = makeDB().db
        XCTAssertNil(sqliteDB.getOrCreateRelation("person", scheme: ["id", "name"]).err)
        XCTAssertNil(sqliteDB.getOrCreateRelation("selected", scheme: ["id"]).err)
        
        let db = TransactionalDatabase(sqliteDB)
        let person = db["person"]
        
        let selected = MemoryTableRelation(scheme: ["id"])
        
        XCTAssertNil(selected.add(["id": 1]).err)
        
        XCTAssertNil(person.add(["id": 1, "name": "Alf"]).err)
        XCTAssertNil(person.add(["id": 2, "name": "Tina"]).err)
        XCTAssertNil(person.add(["id": 3, "name": "Tony"]).err)
        XCTAssertNil(person.add(["id": 4, "name": "Mr. T"]).err)
        
        let selectedName = person.join(selected)
        
        let personObserver = TestAsyncChangeObserver()
        let personRemover = person.addAsyncObserver(personObserver)
        
        let selectedObserver = TestAsyncChangeObserver()
        let selectedRemover = selected.addAsyncObserver(selectedObserver)
        
        let oneName = person.select(Attribute("id") *== 4).project(["name"])
        
        let oneNameObserver = TestAsyncChangeObserver()
        let oneNameRemover = oneName.addAsyncObserver(oneNameObserver)
        
        func reset() {
            func reset(_ observer: TestAsyncChangeObserver) {
                observer.willChangeCount = 0
                observer.addedRows = nil
                observer.removedRows = nil
                observer.error = nil
                observer.didChangeCount = 0
            }
            
            reset(personObserver)
            reset(oneNameObserver)
            reset(selectedObserver)
        }
        
        selectedName.asyncUpdate(true, newValues: ["name": "Alfonzo"])
        CFRunLoopRunOrFail()
        
        reset()
        
        selectedName.asyncUpdate(true, newValues: ["name": "Alfred"])
        CFRunLoopRunOrFail()
        
        XCTAssertEqual(personObserver.willChangeCount, 1)
        XCTAssertEqual(personObserver.addedRows, [["id": 1, "name": "Alfred"]])
        XCTAssertEqual(personObserver.removedRows, [["id": 1, "name": "Alfonzo"]])
        XCTAssertNil(personObserver.error)
        XCTAssertEqual(personObserver.didChangeCount, 1)
        
        XCTAssertEqual(oneNameObserver.willChangeCount, 0)
        XCTAssertEqual(oneNameObserver.addedRows ?? [], [])
        XCTAssertEqual(oneNameObserver.removedRows ?? [], [])
        XCTAssertNil(oneNameObserver.error)
        XCTAssertEqual(oneNameObserver.didChangeCount, 0)
        
        reset()
        
        selected.asyncAdd(["id": 2])
        CFRunLoopRunOrFail()
        
        reset()
        
        selectedName.asyncUpdate(true, newValues: ["name": "Common"])
        CFRunLoopRunOrFail()
        
        XCTAssertEqual(personObserver.willChangeCount, 1)
        XCTAssertEqual(personObserver.addedRows, [["id": 1, "name": "Common"], ["id": 2, "name": "Common"]])
        XCTAssertEqual(personObserver.removedRows, [["id": 1, "name": "Alfred"], ["id": 2, "name": "Tina"]])
        XCTAssertNil(personObserver.error)
        XCTAssertEqual(personObserver.didChangeCount, 1)
        
        XCTAssertEqual(oneNameObserver.willChangeCount, 0)
        XCTAssertEqual(oneNameObserver.addedRows ?? [], [])
        XCTAssertEqual(oneNameObserver.removedRows ?? [], [])
        XCTAssertNil(oneNameObserver.error)
        XCTAssertEqual(oneNameObserver.didChangeCount, 0)
        
        reset()
        
        selected.asyncUpdate(true, newValues: ["id": 4])
        CFRunLoopRunOrFail()
        
        reset()
        
        selectedName.asyncUpdate(true, newValues: ["name": "Mr. Trombone"])
        CFRunLoopRunOrFail()
        
        XCTAssertEqual(personObserver.willChangeCount, 1)
        XCTAssertEqual(personObserver.addedRows, [["id": 4, "name": "Mr. Trombone"]])
        XCTAssertEqual(personObserver.removedRows, [["id": 4, "name": "Mr. T"]])
        XCTAssertNil(personObserver.error)
        XCTAssertEqual(personObserver.didChangeCount, 1)
        
        XCTAssertEqual(oneNameObserver.willChangeCount, 1)
        XCTAssertEqual(oneNameObserver.addedRows, [["name": "Mr. Trombone"]])
        XCTAssertEqual(oneNameObserver.removedRows, [["name": "Mr. T"]])
        XCTAssertNil(oneNameObserver.error)
        XCTAssertEqual(oneNameObserver.didChangeCount, 1)
        
        personRemover()
        selectedRemover()
        oneNameRemover()
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
