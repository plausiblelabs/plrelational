//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import libRelational

class TransactionalDatabaseTests: DBTestCase {
    func testTransactionNotifications() {
        let sqliteDB = makeDB().db.sqliteDatabase
        let db = TransactionalDatabase(sqliteDB)
        let flightsScheme: Scheme = ["number", "pilot", "equipment"]
        let pilotsScheme: Scheme = ["name", "home"]
        
        sqliteDB.createRelation("flights", scheme: flightsScheme)
        sqliteDB.createRelation("pilots", scheme: pilotsScheme)
        
        let flights = db["flights"]
        let pilots = db["pilots"]
        
        var lastFlightsChange: RelationChange?
        _ = flights.addChangeObserver({ lastFlightsChange = $0 })
        
        var lastPilotsChange: RelationChange?
        _ = pilots.addChangeObserver({ lastPilotsChange = $0 })
        
        db.beginTransaction()
        
        flights.add(["number": 1, "pilot": "Jones", "equipment": "777"])
        flights.add(["number": 2, "pilot": "Smith", "equipment": "787"])
        flights.add(["number": 3, "pilot": "Johnson", "equipment": "797"])
        
        pilots.add(["name": "Jones", "home": "New York"])
        pilots.add(["name": "Smith", "home": "Chicago"])
        pilots.add(["name": "Johnson", "home": "Seattle"])
        
        db.endTransaction()
        
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
        
        flights.add(["number": 4, "pilot": "Jones", "equipment": "DC-10"])
        flights.update(Attribute("number") *== RelationValue(1 as Int64), newValues: ["pilot": "Smith"])
        flights.delete(Attribute("equipment") *== "797")
        
        pilots.add(["name": "Horton", "home": "Miami"])
        pilots.update(Attribute("name") *== "Jones", newValues: ["home": "Boston"])
        pilots.delete(Attribute("home") *== "Seattle")
        
        db.endTransaction()
    
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
        let sqliteDB = makeDB().db.sqliteDatabase
        let db = TransactionalDatabase(sqliteDB)
        let flightsScheme: Scheme = ["number", "pilot", "equipment"]
        let pilotsScheme: Scheme = ["name", "home"]
        
        sqliteDB.createRelation("flights", scheme: flightsScheme)
        sqliteDB.createRelation("pilots", scheme: pilotsScheme)
        
        let flights = db["flights"]
        let pilots = db["pilots"]
        
        let (before, after) = db.transactionWithSnapshots({
            flights.add(["number": 1, "pilot": "Jones", "equipment": "777"])
            flights.add(["number": 2, "pilot": "Smith", "equipment": "787"])
            flights.add(["number": 3, "pilot": "Johnson", "equipment": "797"])
            
            pilots.add(["name": "Jones", "home": "New York"])
            pilots.add(["name": "Smith", "home": "Chicago"])
            pilots.add(["name": "Johnson", "home": "Seattle"])
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
        
        db.restoreSnapshot(before)
        
        AssertEqual(flights,
                    MakeRelation(
                        ["number", "pilot", "equipment"]))
        AssertEqual(pilots,
                    MakeRelation(
                        ["name", "home"]))
        
        db.restoreSnapshot(after)
        
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
            pilots.delete(Attribute("name") *== "Jones")
        })
        
        AssertEqual(pilots,
                    MakeRelation(
                        ["name", "home"],
                        ["Smith", "Chicago"],
                        ["Johnson", "Seattle"]))
        
        db.restoreSnapshot(after)
        
        AssertEqual(pilots,
                    MakeRelation(
                        ["name", "home"],
                        ["Jones", "New York"],
                        ["Smith", "Chicago"],
                        ["Johnson", "Seattle"]))
    }
    
    func testAddNotify() {
        let sqliteDB = makeDB().db.sqliteDatabase
        let db = TransactionalDatabase(sqliteDB)
        
        sqliteDB.createRelation("flights", scheme: ["number", "pilot", "equipment"])
        for row in MakeRelation(
            ["number", "pilot", "equipment"],
            ["123",    "Jones", "707"],
            ["124",    "Steve", "727"],
            ["125",    "Martha", "747"],
            ["126",    "Alice", "767"],
            ["127",    "Wendy", "707"]
            ).rows() {
                sqliteDB["flights"]!.add(row.ok!)
        }
        
        let flights = db["flights"]
        
        var lastChange: RelationChange?
        _ = flights.addChangeObserver({ lastChange = $0 })
        
        flights.add(["number": "42", "pilot": "Adams", "equipment": "MD-11"])
        AssertEqual(lastChange?.added,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["42",     "Adams", "MD-11"]))
        AssertEqual(lastChange?.removed, nil)
        
        flights.add(["number": "43", "pilot": "Adams", "equipment": "MD-11"])
        AssertEqual(lastChange?.added,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["43",     "Adams", "MD-11"]))
        AssertEqual(lastChange?.removed, nil)
        
        flights.add(["number": "44", "pilot": "Adams", "equipment": "MD-11"])
        AssertEqual(lastChange?.added,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["44",     "Adams", "MD-11"]))
        AssertEqual(lastChange?.removed, nil)
        
        flights.add(["number": "45", "pilot": "Adams", "equipment": "MD-11"])
        AssertEqual(lastChange?.added,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["45",     "Adams", "MD-11"]))
        AssertEqual(lastChange?.removed, nil)
    }
    
    func testDeleteNotify() {
        let sqliteDB = makeDB().db.sqliteDatabase
        let db = TransactionalDatabase(sqliteDB)
        
        sqliteDB.createRelation("flights", scheme: ["number", "pilot", "equipment"])
        for row in MakeRelation(
            ["number", "pilot", "equipment"],
            ["123",    "Jones", "707"],
            ["124",    "Steve", "727"],
            ["125",    "Martha", "747"],
            ["126",    "Alice", "767"],
            ["127",    "Wendy", "707"]
            ).rows() {
                sqliteDB["flights"]!.add(row.ok!)
        }
        
        let flights = db["flights"]
        
        var lastChange: RelationChange?
        _ = flights.addChangeObserver({ lastChange = $0 })
        
        flights.add(["number": "42", "pilot": "Adams", "equipment": "MD-11"])
        
        flights.delete(Attribute("number") *== "42")
        AssertEqual(lastChange?.removed,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["42",     "Adams", "MD-11"]))
        AssertEqual(lastChange?.added, nil)
        
        
        flights.delete(Attribute("number") *== "123")
        AssertEqual(lastChange?.removed,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["123",    "Jones", "707"]))
        AssertEqual(lastChange?.added, nil)
    }
    
    func testUpdateNotify() {
        let sqliteDB = makeDB().db.sqliteDatabase
        let db = TransactionalDatabase(sqliteDB)
        
        sqliteDB.createRelation("flights", scheme: ["number", "pilot", "equipment"])
        for row in MakeRelation(
            ["number", "pilot", "equipment"],
            ["123",    "Jones", "707"],
            ["124",    "Steve", "727"],
            ["125",    "Martha", "747"],
            ["126",    "Alice", "767"],
            ["127",    "Wendy", "707"]
            ).rows() {
                sqliteDB["flights"]!.add(row.ok!)
        }
        
        let flights = db["flights"]
        
        var lastChange: RelationChange?
        _ = flights.addChangeObserver({ lastChange = $0 })
        
        flights.add(["number": "42", "pilot": "Adams", "equipment": "MD-11"])
        flights.update(Attribute("number") *== "42", newValues: ["equipment": "DC-10"])
        AssertEqual(lastChange?.removed,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["42",     "Adams", "MD-11"]))
        AssertEqual(lastChange?.added,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["42",     "Adams", "DC-10"]))
        
        flights.update(Attribute("number") *== "123", newValues: ["equipment": "DC-10"])
        AssertEqual(lastChange?.removed,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["123",    "Jones", "707"]))
        AssertEqual(lastChange?.added,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["123",    "Jones", "DC-10"]))
        
        flights.update(Attribute("equipment") *== "DC-10", newValues: ["pilot": "JFK"])
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
        let sqlite = makeDB().db.sqliteDatabase
        XCTAssertNil(sqlite.getOrCreateRelation("a", scheme: ["n"]).err)
        XCTAssertNil(sqlite.getOrCreateRelation("b", scheme: ["n"]).err)
        
        let db = TransactionalDatabase(sqlite)
        let a = db["a"]
        let b = db["b"]
        let intersection = a.intersection(b)
        
        dispatch_async(dispatch_get_global_queue(0, 0), {
            for _ in 0..<100 {
                db.beginTransaction()
                a.add(["n": 1])
                b.delete(Attribute("n") *== 1)
                db.endTransaction()
                
                db.beginTransaction()
                b.add(["n": 1])
                a.delete(Attribute("n") *== 1)
                db.endTransaction()
            }
            
            db.beginTransaction()
            a.add(["n": 2])
            b.add(["n": 2])
            db.endTransaction()
        })
        
        var done = false
        while !done {
            for row in intersection.rows() {
                if case QueryRunner.Error.MutatedDuringEnumeration? = row.err {
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
        let sqlite = makeDB().db.sqliteDatabase
        XCTAssertNil(sqlite.getOrCreateRelation("a", scheme: ["n", "m"]).err)
        
        let db = TransactionalDatabase(sqlite)
        let a = db["a"]
        a.add(["n": 1, "m": 1])
        
        dispatch_async(dispatch_get_global_queue(0, 0), {
            for _ in 0..<100 {
                a.update(true, newValues: ["m": 2])
                a.update(true, newValues: ["m": 1])
            }
            a.update(true, newValues: ["n": 2])
            print("done")
        })
        
        var done = false
        while !done {
            for row in a.rows() {
                switch row {
                case .Err(QueryRunner.Error.MutatedDuringEnumeration):
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
        let sqlite = makeDB().db.sqliteDatabase
        XCTAssertNil(sqlite.getOrCreateRelation("a", scheme: ["n"]).err)
        
        let db = TransactionalDatabase(sqlite)
        let a = db["a"]
        
        db.beginTransaction()
        let group = dispatch_group_create()
        dispatch_group_async(group, dispatch_get_global_queue(0, 0), {
            AssertEqual(a, MakeRelation(["n"]))
        })
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER)
        db.endTransaction()
    }
    
    func testTransactionWhileReading() {
        let sqlite = makeDB().db.sqliteDatabase
        XCTAssertNil(sqlite.getOrCreateRelation("a", scheme: ["n"]).err)
        
        let db = TransactionalDatabase(sqlite)
        let a = db["a"]
        
        AssertEqual(a, nil)
        
        let rows = a.rows()
        db.beginTransaction()
        a.add(["n": 1])
        db.endTransaction()
        
        let row = rows.next()
        switch row {
        case .Some(.Err(QueryRunner.Error.MutatedDuringEnumeration)):
            break
        default:
            XCTFail("Unexpected row result: \(row)")
        }
        
        AssertEqual(a,
                    MakeRelation(
                        ["n"],
                        [1]))
    }
}
