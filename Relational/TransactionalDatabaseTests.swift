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
        
        AssertEqual(lastFlightsChange!.added,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        [1, "Jones", "777"],
                        [2, "Smith", "787"],
                        [3, "Johnson", "797"]))
        AssertEqual(lastFlightsChange!.removed, nil)
        AssertEqual(lastPilotsChange!.added,
                    MakeRelation(
                        ["name", "home"],
                        ["Jones", "New York"],
                        ["Smith", "Chicago"],
                        ["Johnson", "Seattle"]))
        AssertEqual(lastPilotsChange!.removed, nil)
        
        db.beginTransaction()
        
        flights.add(["number": 4, "pilot": "Jones", "equipment": "DC-10"])
        flights.update(Attribute("number") *== RelationValue(1 as Int64), newValues: ["pilot": "Smith"])
        flights.delete(Attribute("equipment") *== "797")
        
        pilots.add(["name": "Horton", "home": "Miami"])
        pilots.update(Attribute("name") *== "Jones", newValues: ["home": "Boston"])
        pilots.delete(Attribute("home") *== "Seattle")
        
        db.endTransaction()
    
        AssertEqual(lastFlightsChange!.added,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        [4, "Jones", "DC-10"],
                        [1, "Smith", "777"]))
        AssertEqual(lastFlightsChange!.removed,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        [3, "Johnson", "797"],
                        [1, "Jones", "777"]))
        AssertEqual(lastPilotsChange!.added,
                    MakeRelation(
                        ["name", "home"],
                        ["Horton", "Miami"],
                        ["Jones", "Boston"]))
        AssertEqual(lastPilotsChange!.removed,
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
        AssertEqual(lastChange!.added!,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["42",     "Adams", "MD-11"]))
        AssertEqual(lastChange!.removed, nil)
        
        flights.add(["number": "43", "pilot": "Adams", "equipment": "MD-11"])
        AssertEqual(lastChange!.added!,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["43",     "Adams", "MD-11"]))
        AssertEqual(lastChange!.removed, nil)
        
        flights.add(["number": "44", "pilot": "Adams", "equipment": "MD-11"])
        AssertEqual(lastChange!.added!,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["44",     "Adams", "MD-11"]))
        AssertEqual(lastChange!.removed, nil)
        
        flights.add(["number": "45", "pilot": "Adams", "equipment": "MD-11"])
        AssertEqual(lastChange!.added!,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["45",     "Adams", "MD-11"]))
        AssertEqual(lastChange!.removed, nil)
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
        AssertEqual(lastChange!.removed,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["42",     "Adams", "MD-11"]))
        AssertEqual(lastChange!.added, nil)
        
        
        flights.delete(Attribute("number") *== "123")
        AssertEqual(lastChange!.removed,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["123",    "Jones", "707"]))
        AssertEqual(lastChange!.added, nil)
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
        AssertEqual(lastChange!.removed,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["42",     "Adams", "MD-11"]))
        AssertEqual(lastChange!.added,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["42",     "Adams", "DC-10"]))
        
        flights.update(Attribute("number") *== "123", newValues: ["equipment": "DC-10"])
        AssertEqual(lastChange!.removed,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["123",    "Jones", "707"]))
        AssertEqual(lastChange!.added,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["123",    "Jones", "DC-10"]))
        
        flights.update(Attribute("equipment") *== "DC-10", newValues: ["pilot": "JFK"])
        AssertEqual(lastChange!.removed,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["42",     "Adams", "DC-10"],
                        ["123",    "Jones", "DC-10"]))
        AssertEqual(lastChange!.added,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["42",     "JFK", "DC-10"],
                        ["123",    "JFK", "DC-10"]))
    }
}
