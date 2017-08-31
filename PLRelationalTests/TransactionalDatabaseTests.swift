//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import PLRelational

class TransactionalDatabaseTests: DBTestCase {
    func testTransactionNotifications() {
        let sqliteDB = makeDB().db
        let db = TransactionalDatabase(sqliteDB)
        let flightsScheme: Scheme = ["number", "pilot", "equipment"]
        let pilotsScheme: Scheme = ["name", "home"]
        
        _ = sqliteDB.createRelation("flights", scheme: flightsScheme)
        _ = sqliteDB.createRelation("pilots", scheme: pilotsScheme)
        
        let flights = db["flights"]
        let pilots = db["pilots"]
        
        var lastFlightsChange: RelationChange?
        _ = flights.addChangeObserver({ lastFlightsChange = $0 })
        
        var lastPilotsChange: RelationChange?
        _ = pilots.addChangeObserver({ lastPilotsChange = $0 })
        
        db.beginTransaction()
        
        _ = flights.add(["number": 1, "pilot": "Jones", "equipment": "777"])
        _ = flights.add(["number": 2, "pilot": "Smith", "equipment": "787"])
        _ = flights.add(["number": 3, "pilot": "Johnson", "equipment": "797"])
        
        _ = pilots.add(["name": "Jones", "home": "New York"])
        _ = pilots.add(["name": "Smith", "home": "Chicago"])
        _ = pilots.add(["name": "Johnson", "home": "Seattle"])
        
        _ = db.endTransaction()
        
        AssertEqual(lastFlightsChange?.added,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        [1, "Jones", "777"],
                        [2, "Smith", "787"],
                        [3, "Johnson", "797"]))
        AssertEqual(lastFlightsChange?.removed, nil)
        AssertEqual(lastPilotsChange?.added,
                    MakeRelation(
                        ["name", "home"],
                        ["Jones", "New York"],
                        ["Smith", "Chicago"],
                        ["Johnson", "Seattle"]))
        AssertEqual(lastPilotsChange?.removed, nil)
        
        db.beginTransaction()
        
        _ = flights.add(["number": 4, "pilot": "Jones", "equipment": "DC-10"])
        _ = flights.update(Attribute("number") *== RelationValue(1 as Int64), newValues: ["pilot": "Smith"])
        _ = flights.delete(Attribute("equipment") *== "797")
        
        _ = pilots.add(["name": "Horton", "home": "Miami"])
        _ = pilots.update(Attribute("name") *== "Jones", newValues: ["home": "Boston"])
        _ = pilots.delete(Attribute("home") *== "Seattle")
        
        _ = db.endTransaction()
    
        AssertEqual(lastFlightsChange?.added,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        [4, "Jones", "DC-10"],
                        [1, "Smith", "777"]))
        AssertEqual(lastFlightsChange?.removed,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        [3, "Johnson", "797"],
                        [1, "Jones", "777"]))
        AssertEqual(lastPilotsChange?.added,
                    MakeRelation(
                        ["name", "home"],
                        ["Horton", "Miami"],
                        ["Jones", "Boston"]))
        AssertEqual(lastPilotsChange?.removed,
                    MakeRelation(
                        ["name", "home"],
                        ["Jones", "New York"],
                        ["Johnson", "Seattle"]))
    }
    
    
    func testSnapshots() {
        let sqliteDB = makeDB().db
        let db = TransactionalDatabase(sqliteDB)
        let flightsScheme: Scheme = ["number", "pilot", "equipment"]
        let pilotsScheme: Scheme = ["name", "home"]
        
        _ = sqliteDB.createRelation("flights", scheme: flightsScheme)
        _ = sqliteDB.createRelation("pilots", scheme: pilotsScheme)
        
        let flights = db["flights"]
        let pilots = db["pilots"]
        
        let (before, after) = db.transactionWithSnapshots({
            _ = flights.add(["number": 1, "pilot": "Jones", "equipment": "777"])
            _ = flights.add(["number": 2, "pilot": "Smith", "equipment": "787"])
            _ = flights.add(["number": 3, "pilot": "Johnson", "equipment": "797"])
            
            _ = pilots.add(["name": "Jones", "home": "New York"])
            _ = pilots.add(["name": "Smith", "home": "Chicago"])
            _ = pilots.add(["name": "Johnson", "home": "Seattle"])
        })
        
        AssertEqual(flights,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        [1, "Jones", "777"],
                        [2, "Smith", "787"],
                        [3, "Johnson", "797"]))
        AssertEqual(pilots,
                    MakeRelation(
                        ["name", "home"],
                        ["Jones", "New York"],
                        ["Smith", "Chicago"],
                        ["Johnson", "Seattle"]))
        
        _ = db.restoreSnapshot(before)
        
        AssertEqual(flights,
                    MakeRelation(
                        ["number", "pilot", "equipment"]))
        AssertEqual(pilots,
                    MakeRelation(
                        ["name", "home"]))
        
        _ = db.restoreSnapshot(after)
        
        AssertEqual(flights,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        [1, "Jones", "777"],
                        [2, "Smith", "787"],
                        [3, "Johnson", "797"]))
        AssertEqual(pilots,
                    MakeRelation(
                        ["name", "home"],
                        ["Jones", "New York"],
                        ["Smith", "Chicago"],
                        ["Johnson", "Seattle"]))
        
        db.transaction({
            _ = pilots.delete(Attribute("name") *== "Jones")
        })
        
        AssertEqual(pilots,
                    MakeRelation(
                        ["name", "home"],
                        ["Smith", "Chicago"],
                        ["Johnson", "Seattle"]))
        
        _ = db.restoreSnapshot(after)
        
        AssertEqual(pilots,
                    MakeRelation(
                        ["name", "home"],
                        ["Jones", "New York"],
                        ["Smith", "Chicago"],
                        ["Johnson", "Seattle"]))
    }
    
    func testRestoreSnapshotAfterDeletesOnMultipleRelations() {
        let sqliteDB = makeDB().db
        let db = TransactionalDatabase(sqliteDB)
        
        func createRelation(_ name: String, _ scheme: Scheme) -> MutableRelation {
            let createResult = sqliteDB.createRelation(name, scheme: scheme)
            precondition(createResult.ok != nil)
            return db[name]
        }

        let objects = createRelation("object", ["id", "name", "type"])
        let docItems = createRelation("doc_item", ["id"])
        let docObjects = docItems.join(objects).project(["id", "name"])

        var changes: [RelationChange] = []
        let removal = docObjects.addChangeObserver({ change in
            changes.append(change)
        })
        
        db.transaction{
            _ = objects.add(["id": 1, "name": "One", "type": 0])
            _ = docItems.add(["id": 1])
            _ = objects.add(["id": 2, "name": "Two", "type": 0])
            _ = docItems.add(["id": 2])
        }
        
        XCTAssertEqual(changes.count, 1)
        AssertEqual(changes[0].added,
                    MakeRelation(
                        ["id", "name"],
                        [1, "One"],
                        [2, "Two"]))
        AssertEqual(changes[0].removed, nil)
        changes.removeAll()

        let preDelete = db.takeSnapshot()
        
        db.transaction{
            _ = objects.delete(Attribute("id") *== 1)
            _ = docItems.delete(Attribute("id") *== 1)
        }
        
        XCTAssertEqual(changes.count, 1)
        AssertEqual(changes[0].added, nil)
        AssertEqual(changes[0].removed,
                    MakeRelation(
                        ["id", "name"],
                        [1, "One"]))
        changes.removeAll()

        _ = db.restoreSnapshot(preDelete)

        XCTAssertEqual(changes.count, 1)
        AssertEqual(changes[0].added,
                    MakeRelation(
                        ["id", "name"],
                        [1, "One"]))
        AssertEqual(changes[0].removed, nil)
        changes.removeAll()

        removal()
    }
    
    func testAddNotify() {
        let sqliteDB = makeDB().db
        let db = TransactionalDatabase(sqliteDB)
        
        _ = sqliteDB.createRelation("flights", scheme: ["number", "pilot", "equipment"])
        for row in MakeRelation(
            ["number", "pilot", "equipment"],
            ["123",    "Jones", "707"],
            ["124",    "Steve", "727"],
            ["125",    "Martha", "747"],
            ["126",    "Alice", "767"],
            ["127",    "Wendy", "707"]
            ).rows() {
                _ = sqliteDB["flights"]!.add(row.ok!)
        }
        
        let flights = db["flights"]
        
        var lastChange: RelationChange?
        _ = flights.addChangeObserver({ lastChange = $0 })
        
        _ = flights.add(["number": "42", "pilot": "Adams", "equipment": "MD-11"])
        AssertEqual(lastChange?.added,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["42",     "Adams", "MD-11"]))
        AssertEqual(lastChange?.removed, nil)
        
        _ = flights.add(["number": "43", "pilot": "Adams", "equipment": "MD-11"])
        AssertEqual(lastChange?.added,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["43",     "Adams", "MD-11"]))
        AssertEqual(lastChange?.removed, nil)
        
        _ = flights.add(["number": "44", "pilot": "Adams", "equipment": "MD-11"])
        AssertEqual(lastChange?.added,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["44",     "Adams", "MD-11"]))
        AssertEqual(lastChange?.removed, nil)
        
        _ = flights.add(["number": "45", "pilot": "Adams", "equipment": "MD-11"])
        AssertEqual(lastChange?.added,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["45",     "Adams", "MD-11"]))
        AssertEqual(lastChange?.removed, nil)
    }
    
    func testDeleteNotify() {
        let sqliteDB = makeDB().db
        let db = TransactionalDatabase(sqliteDB)
        
        _ = sqliteDB.createRelation("flights", scheme: ["number", "pilot", "equipment"])
        for row in MakeRelation(
            ["number", "pilot", "equipment"],
            ["123",    "Jones", "707"],
            ["124",    "Steve", "727"],
            ["125",    "Martha", "747"],
            ["126",    "Alice", "767"],
            ["127",    "Wendy", "707"]
            ).rows() {
                _ = sqliteDB["flights"]!.add(row.ok!)
        }
        
        let flights = db["flights"]
        
        var lastChange: RelationChange?
        _ = flights.addChangeObserver({ lastChange = $0 })
        
        _ = flights.add(["number": "42", "pilot": "Adams", "equipment": "MD-11"])
        
        _ = flights.delete(Attribute("number") *== "42")
        AssertEqual(lastChange?.removed,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["42",     "Adams", "MD-11"]))
        AssertEqual(lastChange?.added, nil)
        
        
        _ = flights.delete(Attribute("number") *== "123")
        AssertEqual(lastChange?.removed,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["123",    "Jones", "707"]))
        AssertEqual(lastChange?.added, nil)
    }
    
    func testUpdateNotify() {
        let sqliteDB = makeDB().db
        let db = TransactionalDatabase(sqliteDB)
        
        _ = sqliteDB.createRelation("flights", scheme: ["number", "pilot", "equipment"])
        for row in MakeRelation(
            ["number", "pilot", "equipment"],
            ["123",    "Jones", "707"],
            ["124",    "Steve", "727"],
            ["125",    "Martha", "747"],
            ["126",    "Alice", "767"],
            ["127",    "Wendy", "707"]
            ).rows() {
                _ = sqliteDB["flights"]!.add(row.ok!)
        }
        
        let flights = db["flights"]
        
        var lastChange: RelationChange?
        _ = flights.addChangeObserver({ lastChange = $0 })
        
        _ = flights.add(["number": "42", "pilot": "Adams", "equipment": "MD-11"])
        _ = flights.update(Attribute("number") *== "42", newValues: ["equipment": "DC-10"])
        AssertEqual(lastChange?.removed,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["42",     "Adams", "MD-11"]))
        AssertEqual(lastChange?.added,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["42",     "Adams", "DC-10"]))
        
        _ = flights.update(Attribute("number") *== "123", newValues: ["equipment": "DC-10"])
        AssertEqual(lastChange?.removed,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["123",    "Jones", "707"]))
        AssertEqual(lastChange?.added,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["123",    "Jones", "DC-10"]))
        
        _ = flights.update(Attribute("equipment") *== "DC-10", newValues: ["pilot": "JFK"])
        AssertEqual(lastChange?.removed,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["42",     "Adams", "DC-10"],
                        ["123",    "Jones", "DC-10"]))
        AssertEqual(lastChange?.added,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["42",     "JFK", "DC-10"],
                        ["123",    "JFK", "DC-10"]))
    }
    
    func testConcurrentReadAndWriteTransactions() {
        let sqlite = makeDB().db
        XCTAssertNil(sqlite.getOrCreateRelation("a", scheme: ["n"]).err)
        XCTAssertNil(sqlite.getOrCreateRelation("b", scheme: ["n"]).err)
        
        let db = TransactionalDatabase(sqlite)
        let a = db["a"]
        let b = db["b"]
        let intersection = a.intersection(b)
        
        DispatchQueue.global().async(execute: {
            for _ in 0..<100 {
                db.beginTransaction()
                _ = a.add(["n": 1])
                _ = b.delete(Attribute("n") *== 1)
                _ = db.endTransaction()
                
                db.beginTransaction()
                _ = b.add(["n": 1])
                _ = a.delete(Attribute("n") *== 1)
                _ = db.endTransaction()
            }
            
            db.beginTransaction()
            _ = a.add(["n": 2])
            _ = b.add(["n": 2])
            _ = db.endTransaction()
        })
        
        var done = false
        while !done {
            for row in intersection.rows() {
                if case QueryRunner.Error.mutatedDuringEnumeration? = row.err {
                    continue
                }
                XCTAssertFalse(done)
                XCTAssertNil(row.err)
                XCTAssertEqual(row.ok?["n"], 2)
                done = true
            }
        }
    }
    
    func testConcurrentReadAndWriteNoTransactions() {
        let sqlite = makeDB().db
        XCTAssertNil(sqlite.getOrCreateRelation("a", scheme: ["n", "m"]).err)
        
        let db = TransactionalDatabase(sqlite)
        let a = db["a"]
        _ = a.add(["n": 1, "m": 1])
        
        DispatchQueue.global().async(execute: {
            for _ in 0..<100 {
                _ = a.update(true, newValues: ["m": 2])
                _ = a.update(true, newValues: ["m": 1])
            }
            _ = a.update(true, newValues: ["n": 2])
            print("done")
        })
        
        var done = false
        while !done {
            for row in a.rows() {
                switch row {
                case .Err(QueryRunner.Error.mutatedDuringEnumeration):
                    continue
                case .Err(let err):
                    XCTFail("Unexpected error \(err)")
                case .Ok(let row):
                    if row["n"] == 2 {
                        done = true
                    } else {
                        XCTAssertEqual(row["n"], 1)
                    }
                }
            }
        }
    }
    
    func testConcurrentReadWhileInTransaction() {
        let sqlite = makeDB().db
        XCTAssertNil(sqlite.getOrCreateRelation("a", scheme: ["n"]).err)
        
        let db = TransactionalDatabase(sqlite)
        let a = db["a"]
        
        db.beginTransaction()
        let group = DispatchGroup()
        DispatchQueue.global().async(group: group, execute: {
            AssertEqual(a, MakeRelation(["n"]))
        })
        _ = group.wait(timeout: DispatchTime.distantFuture)
        _ = db.endTransaction()
    }
    
    func testTransactionWhileReading() {
        let sqlite = makeDB().db
        XCTAssertNil(sqlite.getOrCreateRelation("a", scheme: ["n"]).err)
        
        let db = TransactionalDatabase(sqlite)
        let a = db["a"]
        
        AssertEqual(a, nil)
        
        let rows = a.rows()
        db.beginTransaction()
        _ = a.add(["n": 1])
        _ = db.endTransaction()
        
        let row = rows.next()
        switch row {
        case .some(.Err(QueryRunner.Error.mutatedDuringEnumeration)):
            break
        default:
            XCTFail("Unexpected row result: \(String(describing: row))")
        }
        
        AssertEqual(a,
                    MakeRelation(
                        ["n"],
                        [1]))
    }
    
    func testDeltas() {
        let sqlite = makeDB().db
        XCTAssertNil(sqlite.getOrCreateRelation("a", scheme: ["n"]).err)
        
        let db = TransactionalDatabase(sqlite)
        let a = db["a"]
        
        let snap1 = db.takeSnapshot()
        _ = a.add(["n": 1])
        let snap2 = db.takeSnapshot()
        let delta1 = db.computeDelta(from: snap1, to: snap2)
        
        _ = a.add(["n": 2])
        let snap3 = db.takeSnapshot()
        let delta2 = db.computeDelta(from: snap2, to: snap3)
        
        _ = db.apply(delta: delta1.reversed)
        AssertEqual(a, MakeRelation(["n"], [2]))
        
        _ = db.apply(delta: delta2.reversed)
        AssertEqual(a, nil)
        
        _ = db.apply(delta: delta1)
        AssertEqual(a, MakeRelation(["n"], [1]))
        
        _ = db.apply(delta: delta2)
        AssertEqual(a, MakeRelation(["n"], [1], [2]))
    }
    
    func testAsyncDeltas() {
        let runloop = CFRunLoopGetCurrent()
        
        let sqlite = makeDB().db
        XCTAssertNil(sqlite.getOrCreateRelation("a", scheme: ["n"]).err)
        
        let db = TransactionalDatabase(sqlite)
        let a = db["a"]
        
        var snap1: TransactionalDatabaseSnapshot!
        AsyncManager.currentInstance.registerCheckpoint({ snap1 = db.takeSnapshot() })
        a.asyncAdd(["n": 1])
        
        var snap2: TransactionalDatabaseSnapshot!
        let delta1Promise = Promise<TransactionalDatabaseDelta>()
        AsyncManager.currentInstance.registerCheckpoint({ snap2 = db.takeSnapshot() })
        AsyncManager.currentInstance.registerCheckpoint({ delta1Promise.fulfill(db.computeDelta(from: snap1, to: snap2)) })
        
        a.asyncAdd(["n": 2])
        
        var snap3: TransactionalDatabaseSnapshot!
        let delta2Promise = Promise<TransactionalDatabaseDelta>()
        AsyncManager.currentInstance.registerCheckpoint({ snap3 = db.takeSnapshot() })
        AsyncManager.currentInstance.registerCheckpoint({ delta2Promise.fulfill(db.computeDelta(from: snap2, to: snap3)) })
        
        AsyncManager.currentInstance.registerCheckpoint({ AssertEqual(a, MakeRelation(["n"], [1], [2])) })
        
        AsyncManager.currentInstance.registerCheckpoint({ CFRunLoopStop(runloop) })
        CFRunLoopRun()
        
        db.asyncApply(delta: delta1Promise.get().reversed)
        AsyncManager.currentInstance.registerCheckpoint({ AssertEqual(a, MakeRelation(["n"], [2])) })
        
        db.asyncApply(delta: delta2Promise.get().reversed)
        AsyncManager.currentInstance.registerCheckpoint({ AssertEqual(a, MakeRelation(["n"])) })
        
        db.asyncApply(delta: delta1Promise.get())
        AsyncManager.currentInstance.registerCheckpoint({ AssertEqual(a, MakeRelation(["n"], [1])) })
        
        db.asyncApply(delta: delta2Promise.get())
        AsyncManager.currentInstance.registerCheckpoint({ AssertEqual(a, MakeRelation(["n"], [1], [2])) })
        
        AsyncManager.currentInstance.registerCheckpoint({ CFRunLoopStop(runloop) })
        CFRunLoopRun()
    }
    
    func testAsyncDeltasWithObservers() {
        let runloop = CFRunLoopGetCurrent()
        
        let sqlite = makeDB().db
        XCTAssertNil(sqlite.getOrCreateRelation("a", scheme: ["n"]).err)
        
        let db = TransactionalDatabase(sqlite)
        let a = db["a"]
        
        class DummyObserver: AsyncRelationChangeCoalescedObserver {
            func relationWillChange(_ relation: Relation) {}
            func relationDidChange(_ relation: Relation, result: Result<RowChange, RelationError>) {}
        }
        
        let remover = a.addAsyncObserver(DummyObserver())
        
        var snap1: TransactionalDatabaseSnapshot!
        AsyncManager.currentInstance.registerCheckpoint({ snap1 = db.takeSnapshot() })
        a.asyncAdd(["n": 1])
        
        var snap2: TransactionalDatabaseSnapshot!
        let delta1Promise = Promise<TransactionalDatabaseDelta>()
        AsyncManager.currentInstance.registerCheckpoint({ snap2 = db.takeSnapshot() })
        AsyncManager.currentInstance.registerCheckpoint({ delta1Promise.fulfill(db.computeDelta(from: snap1, to: snap2)) })
        
        a.asyncAdd(["n": 2])
        
        var snap3: TransactionalDatabaseSnapshot!
        let delta2Promise = Promise<TransactionalDatabaseDelta>()
        AsyncManager.currentInstance.registerCheckpoint({ snap3 = db.takeSnapshot() })
        AsyncManager.currentInstance.registerCheckpoint({ delta2Promise.fulfill(db.computeDelta(from: snap2, to: snap3)) })
        
        AsyncManager.currentInstance.registerCheckpoint({ AssertEqual(a, MakeRelation(["n"], [1], [2])) })
        
        AsyncManager.currentInstance.registerCheckpoint({ CFRunLoopStop(runloop) })
        CFRunLoopRun()
        
        db.asyncApply(delta: delta1Promise.get().reversed)
        AsyncManager.currentInstance.registerCheckpoint({ AssertEqual(a, MakeRelation(["n"], [2])) })
        
        db.asyncApply(delta: delta2Promise.get().reversed)
        AsyncManager.currentInstance.registerCheckpoint({ AssertEqual(a, MakeRelation(["n"])) })
        
        db.asyncApply(delta: delta1Promise.get())
        AsyncManager.currentInstance.registerCheckpoint({ AssertEqual(a, MakeRelation(["n"], [1])) })
        
        db.asyncApply(delta: delta2Promise.get())
        AsyncManager.currentInstance.registerCheckpoint({ AssertEqual(a, MakeRelation(["n"], [1], [2])) })
        
        AsyncManager.currentInstance.registerCheckpoint({ CFRunLoopStop(runloop) })
        CFRunLoopRun()
        
        remover()
    }
}
