//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import PLRelational

class ChangeLoggingDatabaseTests: DBTestCase {
    func testBare() {
        let underlying = MakeRelation(
            ["number", "pilot", "equipment"],
            ["123",    "Jones", "707"],
            ["124",    "Steve", "727"],
            ["125",    "Martha", "747"],
            ["126",    "Alice", "767"],
            ["127",    "Wendy", "707"]
        )
        
        let loggingRelation = ChangeLoggingRelation(baseRelation: underlying)
        AssertEqual(underlying, loggingRelation)
    }
    
    func testAdd() {
        let underlying = MakeRelation(
            ["number", "pilot", "equipment"],
            ["123",    "Jones", "707"],
            ["124",    "Steve", "727"],
            ["125",    "Martha", "747"],
            ["126",    "Alice", "767"],
            ["127",    "Wendy", "707"]
        )
        
        let loggingRelation = ChangeLoggingRelation(baseRelation: underlying)
        
        _ = loggingRelation.add(["number": "42", "pilot": "Adams", "equipment": "MD-11"])
        AssertEqual(loggingRelation,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["123",    "Jones", "707"],
                        ["124",    "Steve", "727"],
                        ["125",    "Martha", "747"],
                        ["126",    "Alice", "767"],
                        ["127",    "Wendy", "707"],
                        ["42",     "Adams", "MD-11"]
            ))
        
        _ = loggingRelation.add(["number": "43", "pilot": "Adams", "equipment": "MD-11"])
        _ = loggingRelation.add(["number": "44", "pilot": "Adams", "equipment": "MD-11"])
        _ = loggingRelation.add(["number": "45", "pilot": "Adams", "equipment": "MD-11"])
        AssertEqual(loggingRelation,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["123",    "Jones", "707"],
                        ["124",    "Steve", "727"],
                        ["125",    "Martha", "747"],
                        ["126",    "Alice", "767"],
                        ["127",    "Wendy", "707"],
                        ["42",     "Adams", "MD-11"],
                        ["43",     "Adams", "MD-11"],
                        ["44",     "Adams", "MD-11"],
                        ["45",     "Adams", "MD-11"]
            ))
    }
    
    func testAddNotify() {
        let underlying = MakeRelation(
            ["number", "pilot", "equipment"],
            ["123",    "Jones", "707"],
            ["124",    "Steve", "727"],
            ["125",    "Martha", "747"],
            ["126",    "Alice", "767"],
            ["127",    "Wendy", "707"]
        )
        
        let loggingRelation = ChangeLoggingRelation(baseRelation: underlying)
        
        var lastChange: RelationChange?
        _ = loggingRelation.addChangeObserver({ lastChange = $0 })
        
        _ = loggingRelation.add(["number": "42", "pilot": "Adams", "equipment": "MD-11"])
        AssertEqual(lastChange?.added,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["42",     "Adams", "MD-11"]))
        AssertEqual(lastChange?.removed, nil)
        
        _ = loggingRelation.add(["number": "43", "pilot": "Adams", "equipment": "MD-11"])
        AssertEqual(lastChange?.added,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["43",     "Adams", "MD-11"]))
        AssertEqual(lastChange?.removed, nil)
        
        _ = loggingRelation.add(["number": "44", "pilot": "Adams", "equipment": "MD-11"])
        AssertEqual(lastChange?.added,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["44",     "Adams", "MD-11"]))
        AssertEqual(lastChange?.removed, nil)
        
        _ = loggingRelation.add(["number": "45", "pilot": "Adams", "equipment": "MD-11"])
        AssertEqual(lastChange?.added,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["45",     "Adams", "MD-11"]))
        AssertEqual(lastChange?.removed, nil)
    }
    
    func testDelete() {
        let underlying = MakeRelation(
            ["number", "pilot", "equipment"],
            ["123",    "Jones", "707"],
            ["124",    "Steve", "727"],
            ["125",    "Martha", "747"],
            ["126",    "Alice", "767"],
            ["127",    "Wendy", "707"]
        )
        
        let loggingRelation = ChangeLoggingRelation(baseRelation: underlying)
        
        _ = loggingRelation.add(["number": "42", "pilot": "Adams", "equipment": "MD-11"])
        AssertEqual(loggingRelation,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["123",    "Jones", "707"],
                        ["124",    "Steve", "727"],
                        ["125",    "Martha", "747"],
                        ["126",    "Alice", "767"],
                        ["127",    "Wendy", "707"],
                        ["42",     "Adams", "MD-11"]
            ))
        
        _ = loggingRelation.delete(Attribute("number") *== "42")
        AssertEqual(loggingRelation,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["123",    "Jones", "707"],
                        ["124",    "Steve", "727"],
                        ["125",    "Martha", "747"],
                        ["126",    "Alice", "767"],
                        ["127",    "Wendy", "707"]
            ))
        
        _ = loggingRelation.delete(Attribute("number") *== "123")
        AssertEqual(loggingRelation,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["124",    "Steve", "727"],
                        ["125",    "Martha", "747"],
                        ["126",    "Alice", "767"],
                        ["127",    "Wendy", "707"]
            ))
    }
    
    func testDeleteNotify() {
        let underlying = MakeRelation(
            ["number", "pilot", "equipment"],
            ["123",    "Jones", "707"],
            ["124",    "Steve", "727"],
            ["125",    "Martha", "747"],
            ["126",    "Alice", "767"],
            ["127",    "Wendy", "707"]
        )
        
        let loggingRelation = ChangeLoggingRelation(baseRelation: underlying)
        
        var lastChange: RelationChange?
        _ = loggingRelation.addChangeObserver({ lastChange = $0 })
        
        _ = loggingRelation.add(["number": "42", "pilot": "Adams", "equipment": "MD-11"])
        
        _ = loggingRelation.delete(Attribute("number") *== "42")
        AssertEqual(lastChange?.removed,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["42",     "Adams", "MD-11"]))
        AssertEqual(lastChange?.added, nil)
        
        
        _ = loggingRelation.delete(Attribute("number") *== "123")
        AssertEqual(lastChange?.removed,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["123",    "Jones", "707"]))
        AssertEqual(lastChange?.added, nil)
    }
    
    func testUpdate() {
        let underlying = MakeRelation(
            ["number", "pilot", "equipment"],
            ["123",    "Jones", "707"],
            ["124",    "Steve", "727"],
            ["125",    "Martha", "747"],
            ["126",    "Alice", "767"],
            ["127",    "Wendy", "707"]
        )
        
        let loggingRelation = ChangeLoggingRelation(baseRelation: underlying)
        
        _ = loggingRelation.add(["number": "42", "pilot": "Adams", "equipment": "MD-11"])
        _ = loggingRelation.update(Attribute("number") *== "42", newValues: ["equipment": "DC-10"])
        AssertEqual(loggingRelation,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["123",    "Jones", "707"],
                        ["124",    "Steve", "727"],
                        ["125",    "Martha", "747"],
                        ["126",    "Alice", "767"],
                        ["127",    "Wendy", "707"],
                        ["42",     "Adams", "DC-10"]
            ))
        
        _ = loggingRelation.update(Attribute("number") *== "123", newValues: ["equipment": "DC-10"])
        AssertEqual(loggingRelation,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["123",    "Jones", "DC-10"],
                        ["124",    "Steve", "727"],
                        ["125",    "Martha", "747"],
                        ["126",    "Alice", "767"],
                        ["127",    "Wendy", "707"],
                        ["42",     "Adams", "DC-10"]
            ))
        
        _ = loggingRelation.update(Attribute("equipment") *== "DC-10", newValues: ["pilot": "JFK"])
        AssertEqual(loggingRelation,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["123",    "JFK",   "DC-10"],
                        ["124",    "Steve", "727"],
                        ["125",    "Martha", "747"],
                        ["126",    "Alice", "767"],
                        ["127",    "Wendy", "707"],
                        ["42",     "JFK",   "DC-10"]
            ))
    }
    
    func testUpdateNotify() {
        let underlying = MakeRelation(
            ["number", "pilot", "equipment"],
            ["123",    "Jones", "707"],
            ["124",    "Steve", "727"],
            ["125",    "Martha", "747"],
            ["126",    "Alice", "767"],
            ["127",    "Wendy", "707"]
        )
        
        let loggingRelation = ChangeLoggingRelation(baseRelation: underlying)
        
        var lastChange: RelationChange?
        _ = loggingRelation.addChangeObserver({ lastChange = $0 })
        
        _ = loggingRelation.add(["number": "42", "pilot": "Adams", "equipment": "MD-11"])
        _ = loggingRelation.update(Attribute("number") *== "42", newValues: ["equipment": "DC-10"])
        AssertEqual(lastChange?.removed,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["42",     "Adams", "MD-11"]))
        AssertEqual(lastChange?.added,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["42",     "Adams", "DC-10"]))
        
        _ = loggingRelation.update(Attribute("number") *== "123", newValues: ["equipment": "DC-10"])
        AssertEqual(lastChange?.removed,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["123",    "Jones", "707"]))
        AssertEqual(lastChange?.added,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["123",    "Jones", "DC-10"]))
        
        _ = loggingRelation.update(Attribute("equipment") *== "DC-10", newValues: ["pilot": "JFK"])
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
    
    func verifySaveRelation(table: StoredRelation) {
        let loggingRelation = ChangeLoggingRelation(baseRelation: table)
        var referenceRelation = ConcreteRelation(scheme: table.scheme)
        
        func add(_ row: Row) {
            _ = loggingRelation.add(row)
            _ = referenceRelation.add(row)
        }
        
        func delete(_ query: SelectExpression) {
            _ = loggingRelation.delete(query)
            _ = referenceRelation.delete(query)
        }
        
        func update(_ query: SelectExpression, _ newValues: Row) {
            _ = loggingRelation.update(query, newValues: newValues)
            _ = referenceRelation.update(query, newValues: newValues)
        }
        
        AssertEqual(loggingRelation,
                    MakeRelation(
                        ["number", "pilot", "equipment"]))
        AssertEqual(table,
                    MakeRelation(
                        ["number", "pilot", "equipment"]))
        
        XCTAssertNil(loggingRelation.save().err)
        
        AssertEqual(loggingRelation,
                    MakeRelation(
                        ["number", "pilot", "equipment"]))
        AssertEqual(table,
                    MakeRelation(
                        ["number", "pilot", "equipment"]))
        
        add(["number": "1", "pilot": "Pat", "equipment": "A380"])
        add(["number": "2", "pilot": "Sam", "equipment": "A320"])
        add(["number": "3", "pilot": "Sue", "equipment": "A340"])
        
        AssertEqual(table,
                    MakeRelation(
                        ["number", "pilot", "equipment"]))
        AssertEqual(loggingRelation, referenceRelation)
        
        XCTAssertNil(loggingRelation.save().err)
        
        AssertEqual(table, loggingRelation)
        AssertEqual(table, referenceRelation)
        
        add(["number": "4", "pilot": "Tim", "equipment": "A340"])
        delete(Attribute("equipment") *== "A340")
        add(["number": "5", "pilot": "Ham", "equipment": "A340"])
        add(["number": "6", "pilot": "Ham", "equipment": "A340"])
        update(Attribute("pilot") *== "Ham", ["pilot": "Stan"])
        add(["number": "7", "pilot": "Ham", "equipment": "A340"])
        delete(Attribute("pilot") *== "Ham")
        add(["number": "7", "pilot": "Stan", "equipment": "A340"])
        
        AssertEqual(loggingRelation, referenceRelation)
        XCTAssertNil(loggingRelation.save().err)
        AssertEqual(table, referenceRelation)
        AssertEqual(table, loggingRelation)
    }
    
    func testSaveRelation() {
        let scheme: Scheme = ["number", "pilot", "equipment"]
        
        let sqliteDB = makeDB().db
        let sqliteTable = sqliteDB.getOrCreateRelation("flights", scheme: scheme).ok!
        verifySaveRelation(table: sqliteTable)
        
        let plistDB = makePlistDB("flights", scheme)
        verifySaveRelation(table: plistDB["flights"]!)
    }
    
    func verifyDatabaseBasics(_ storedDB: StoredDatabase, _ storedRelation: StoredRelation) {
        let db = ChangeLoggingDatabase(storedDB)
        
        var referenceRelation = ConcreteRelation(scheme: storedRelation.scheme)
        
        func add(_ row: Row) {
            _ = db.transaction({
                _ = $0["flights"].add(row)
            })
            _ = referenceRelation.add(row)
        }
        
        func delete(_ query: SelectExpression) {
            _ = db.transaction({
                _ = $0["flights"].delete(query)
            })
            _ = referenceRelation.delete(query)
        }
        
        func update(_ query: SelectExpression, _ newValues: Row) {
            _ = db.transaction({
                _ = $0["flights"].update(query, newValues: newValues)
            })
            _ = referenceRelation.update(query, newValues: newValues)
        }
        
        AssertEqual(db["flights"],
                    MakeRelation(
                        ["number", "pilot", "equipment"]))
        AssertEqual(storedRelation,
                    MakeRelation(
                        ["number", "pilot", "equipment"]))
        
        XCTAssertNil(db.save().err)
        
        AssertEqual(db["flights"],
                    MakeRelation(
                        ["number", "pilot", "equipment"]))
        AssertEqual(storedRelation,
                    MakeRelation(
                        ["number", "pilot", "equipment"]))
        
        add(["number": "1", "pilot": "Pat", "equipment": "A380"])
        add(["number": "2", "pilot": "Sam", "equipment": "A320"])
        add(["number": "3", "pilot": "Sue", "equipment": "A340"])
        
        AssertEqual(storedRelation,
                    MakeRelation(
                        ["number", "pilot", "equipment"]))
        AssertEqual(db["flights"], referenceRelation)
        
        XCTAssertNil(db.save().err)
        
        AssertEqual(storedRelation, db["flights"])
        AssertEqual(storedRelation, referenceRelation)
        
        add(["number": "4", "pilot": "Tim", "equipment": "A340"])
        delete(Attribute("equipment") *== "A340")
        add(["number": "5", "pilot": "Ham", "equipment": "A340"])
        add(["number": "6", "pilot": "Ham", "equipment": "A340"])
        update(Attribute("pilot") *== "Ham", ["pilot": "Stan"])
        add(["number": "7", "pilot": "Ham", "equipment": "A340"])
        delete(Attribute("pilot") *== "Ham")
        add(["number": "7", "pilot": "Stan", "equipment": "A340"])
        
        AssertEqual(db["flights"], referenceRelation)
        XCTAssertNil(db.save().err)
        AssertEqual(storedRelation, referenceRelation)
        AssertEqual(storedRelation, db["flights"])
    }
    
    func testDatabaseBasics() {
        let scheme: Scheme = ["number", "pilot", "equipment"]
        
        let sqliteDB = makeDB().db
        _ = sqliteDB.createRelation("flights", scheme: scheme)
        verifyDatabaseBasics(sqliteDB, sqliteDB["flights"]!)
        
        let plistDB = makePlistDB("flights", scheme)
        verifyDatabaseBasics(plistDB, plistDB["flights"]!)
    }
    
    func verifyTransactions(_ storedDB: StoredDatabase, _ storedFlights: StoredRelation, _ storedPilots: StoredRelation) {
        let db = ChangeLoggingDatabase(storedDB)
        
        _ = db.transaction({
            let flights = $0["flights"]
            let pilots = $0["pilots"]
            
            _ = flights.add(["number": 1, "pilot": "Jones", "equipment": "777"])
            _ = flights.add(["number": 2, "pilot": "Smith", "equipment": "787"])
            _ = flights.add(["number": 3, "pilot": "Johnson", "equipment": "797"])
            
            _ = pilots.add(["name": "Jones", "home": "New York"])
            _ = pilots.add(["name": "Smith", "home": "Chicago"])
            _ = pilots.add(["name": "Johnson", "home": "Seattle"])
            
            // Assert that the database hasn't changed yet
            AssertEqual(db["flights"],
                MakeRelation(["number", "pilot", "equipment"]))
            AssertEqual(db["pilots"],
                MakeRelation(["name", "home"]))
            
            // But the local relations have
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
        })
        
        // Now the database should change
        AssertEqual(db["flights"],
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        [1, "Jones", "777"],
                        [2, "Smith", "787"],
                        [3, "Johnson", "797"]))
        AssertEqual(db["pilots"],
                    MakeRelation(
                        ["name", "home"],
                        ["Jones", "New York"],
                        ["Smith", "Chicago"],
                        ["Johnson", "Seattle"]))
        
        XCTAssertNil(db.save().err)
        
        // And finally the stored database should change too
        AssertEqual(storedFlights,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        [1, "Jones", "777"],
                        [2, "Smith", "787"],
                        [3, "Johnson", "797"]))
        AssertEqual(storedPilots,
                    MakeRelation(
                        ["name", "home"],
                        ["Jones", "New York"],
                        ["Smith", "Chicago"],
                        ["Johnson", "Seattle"]))
        
        _ = db.transaction({
            let flights = $0["flights"]
            let pilots = $0["pilots"]
            
            _ = flights.add(["number": 4, "pilot": "Jones", "equipment": "DC-10"])
            _ = flights.update(Attribute("number") *== RelationValue(1 as Int64), newValues: ["pilot": "Smith"])
            _ = flights.delete(Attribute("equipment") *== "797")
            
            _ = pilots.add(["name": "Horton", "home": "Miami"])
            _ = pilots.update(Attribute("name") *== "Jones", newValues: ["home": "Boston"])
            _ = pilots.delete(Attribute("home") *== "Seattle")
            
            // Assert that the database still has the old data
            AssertEqual(db["flights"],
                MakeRelation(
                    ["number", "pilot", "equipment"],
                    [1, "Jones", "777"],
                    [2, "Smith", "787"],
                    [3, "Johnson", "797"]))
            AssertEqual(db["pilots"],
                MakeRelation(
                    ["name", "home"],
                    ["Jones", "New York"],
                    ["Smith", "Chicago"],
                    ["Johnson", "Seattle"]))
            
            // But the local relations have the new data
            AssertEqual(flights,
                MakeRelation(
                    ["number", "pilot", "equipment"],
                    [1, "Smith", "777"],
                    [2, "Smith", "787"],
                    [4, "Jones", "DC-10"]))
            AssertEqual(pilots,
                MakeRelation(
                    ["name", "home"],
                    ["Jones", "Boston"],
                    ["Smith", "Chicago"],
                    ["Horton", "Miami"]))
        })
        
        // Now the database should have the new data
        AssertEqual(db["flights"],
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        [1, "Smith", "777"],
                        [2, "Smith", "787"],
                        [4, "Jones", "DC-10"]))
        AssertEqual(db["pilots"],
                    MakeRelation(
                        ["name", "home"],
                        ["Jones", "Boston"],
                        ["Smith", "Chicago"],
                        ["Horton", "Miami"]))
        
        // And the stored databate should still have the old data
        AssertEqual(storedFlights,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        [1, "Jones", "777"],
                        [2, "Smith", "787"],
                        [3, "Johnson", "797"]))
        AssertEqual(storedPilots,
                    MakeRelation(
                        ["name", "home"],
                        ["Jones", "New York"],
                        ["Smith", "Chicago"],
                        ["Johnson", "Seattle"]))
        
        XCTAssertNil(db.save().err)
        
        // Finally, the stored database should have the new data after saving
        AssertEqual(storedFlights,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        [1, "Smith", "777"],
                        [2, "Smith", "787"],
                        [4, "Jones", "DC-10"]))
        AssertEqual(storedPilots,
                    MakeRelation(
                        ["name", "home"],
                        ["Jones", "Boston"],
                        ["Smith", "Chicago"],
                        ["Horton", "Miami"]))
    }
    
    func testTransactions() {
        let flightsScheme: Scheme = ["number", "pilot", "equipment"]
        let pilotsScheme: Scheme = ["name", "home"]
        
        let sqliteDB = makeDB().db
        let sqliteFlights = sqliteDB.createRelation("flights", scheme: flightsScheme).ok!
        let sqlitePilots = sqliteDB.createRelation("pilots", scheme: pilotsScheme).ok!
        verifyTransactions(sqliteDB, sqliteFlights, sqlitePilots)
        
        let plistDB = makePlistDB(specs: [
            .file(name: "flights", path: "flights.plist", scheme: flightsScheme),
            .file(name: "pilots", path: "pilots.plist", scheme: pilotsScheme)
        ])
        verifyTransactions(plistDB, plistDB["flights"]!, plistDB["pilots"]!)
    }
    
    func testTransactionNotifications() {
        let sqliteDB = makeDB().db
        let db = ChangeLoggingDatabase(sqliteDB)
        let flightsScheme: Scheme = ["number", "pilot", "equipment"]
        let pilotsScheme: Scheme = ["name", "home"]
        
        _ = sqliteDB.createRelation("flights", scheme: flightsScheme)
        _ = sqliteDB.createRelation("pilots", scheme: pilotsScheme)
        
        var lastFlightsChange: RelationChange?
        _ = db["flights"].addChangeObserver({ lastFlightsChange = $0 })
        
        var lastPilotsChange: RelationChange?
        _ = db["pilots"].addChangeObserver({ lastPilotsChange = $0 })
        
        _ = db.transaction({
            let flights = $0["flights"]
            let pilots = $0["pilots"]
            
            _ = flights.add(["number": 1, "pilot": "Jones", "equipment": "777"])
            _ = flights.add(["number": 2, "pilot": "Smith", "equipment": "787"])
            _ = flights.add(["number": 3, "pilot": "Johnson", "equipment": "797"])
            
            _ = pilots.add(["name": "Jones", "home": "New York"])
            _ = pilots.add(["name": "Smith", "home": "Chicago"])
            _ = pilots.add(["name": "Johnson", "home": "Seattle"])
        })
        
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
        
        _ = db.transaction({
            let flights = $0["flights"]
            let pilots = $0["pilots"]
            
            _ = flights.add(["number": 4, "pilot": "Jones", "equipment": "DC-10"])
            _ = flights.update(Attribute("number") *== RelationValue(1 as Int64), newValues: ["pilot": "Smith"])
            _ = flights.delete(Attribute("equipment") *== "797")
            
            _ = pilots.add(["name": "Horton", "home": "Miami"])
            _ = pilots.update(Attribute("name") *== "Jones", newValues: ["home": "Boston"])
            _ = pilots.delete(Attribute("home") *== "Seattle")
        })
        
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
        let db = ChangeLoggingDatabase(sqliteDB)
        let flightsScheme: Scheme = ["number", "pilot", "equipment"]
        let pilotsScheme: Scheme = ["name", "home"]
        
        _ = sqliteDB.createRelation("flights", scheme: flightsScheme)
        _ = sqliteDB.createRelation("pilots", scheme: pilotsScheme)
        
        var snapshots: [(ChangeLoggingDatabaseSnapshot, Relation, Relation)] = []
        
        snapshots.append((db.takeSnapshot(), MakeRelation(["number", "pilot", "equipment"]), MakeRelation(["name", "home"])))
        
        _ = db.transaction({
            let flights = $0["flights"]
            let pilots = $0["pilots"]
            
            _ = flights.add(["number": 1, "pilot": "Jones", "equipment": "777"])
            _ = flights.add(["number": 2, "pilot": "Smith", "equipment": "787"])
            _ = flights.add(["number": 3, "pilot": "Johnson", "equipment": "797"])
            
            _ = pilots.add(["name": "Jones", "home": "New York"])
            _ = pilots.add(["name": "Smith", "home": "Chicago"])
            _ = pilots.add(["name": "Johnson", "home": "Seattle"])
        })
        
        snapshots.append((db.takeSnapshot(),
            MakeRelation(
                ["number", "pilot", "equipment"],
                [1, "Jones", "777"],
                [2, "Smith", "787"],
                [3, "Johnson", "797"]),
            MakeRelation(
                ["name", "home"],
                ["Jones", "New York"],
                ["Smith", "Chicago"],
                ["Johnson", "Seattle"])))
        
        
        _ = db.transaction({
            let flights = $0["flights"]
            let pilots = $0["pilots"]
            
            _ = flights.add(["number": 4, "pilot": "Jones", "equipment": "DC-10"])
            _ = flights.update(Attribute("number") *== RelationValue(1 as Int64), newValues: ["pilot": "Smith"])
            _ = flights.delete(Attribute("equipment") *== "797")
            
            _ = pilots.add(["name": "Horton", "home": "Miami"])
            _ = pilots.update(Attribute("name") *== "Jones", newValues: ["home": "Boston"])
            _ = pilots.delete(Attribute("home") *== "Seattle")
        })
        
        snapshots.append((db.takeSnapshot(),
            MakeRelation(
                ["number", "pilot", "equipment"],
                [1, "Smith", "777"],
                [2, "Smith", "787"],
                [4, "Jones", "DC-10"]),
            MakeRelation(
                ["name", "home"],
                ["Jones", "Boston"],
                ["Smith", "Chicago"],
                ["Horton", "Miami"])))
        
        for (snapshot, flights, pilots) in snapshots + snapshots.reversed() {
            _ = db.restoreSnapshot(snapshot)
            AssertEqual(db["flights"], flights)
            AssertEqual(db["pilots"], pilots)
        }
    }
    
    func testTransactionSnapshots() {
        let sqliteDB = makeDB().db
        let db = ChangeLoggingDatabase(sqliteDB)
        let flightsScheme: Scheme = ["number", "pilot", "equipment"]
        let pilotsScheme: Scheme = ["name", "home"]
        
        _ = sqliteDB.createRelation("flights", scheme: flightsScheme)
        _ = sqliteDB.createRelation("pilots", scheme: pilotsScheme)
        
        let (before, after) = db.transactionWithSnapshots({
            let flights = $0["flights"]
            let pilots = $0["pilots"]
            
            _ = flights.add(["number": 1, "pilot": "Jones", "equipment": "777"])
            _ = flights.add(["number": 2, "pilot": "Smith", "equipment": "787"])
            _ = flights.add(["number": 3, "pilot": "Johnson", "equipment": "797"])
            
            _ = pilots.add(["name": "Jones", "home": "New York"])
            _ = pilots.add(["name": "Smith", "home": "Chicago"])
            _ = pilots.add(["name": "Johnson", "home": "Seattle"])
        })
        
        AssertEqual(db["flights"],
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        [1, "Jones", "777"],
                        [2, "Smith", "787"],
                        [3, "Johnson", "797"]))
        AssertEqual(db["pilots"],
                    MakeRelation(
                        ["name", "home"],
                        ["Jones", "New York"],
                        ["Smith", "Chicago"],
                        ["Johnson", "Seattle"]))
        
        _ = db.restoreSnapshot(before)
        
        AssertEqual(db["flights"],
                    MakeRelation(
                        ["number", "pilot", "equipment"]))
        AssertEqual(db["pilots"],
                    MakeRelation(
                        ["name", "home"]))
        
        _ = db.restoreSnapshot(after)
        
        AssertEqual(db["flights"],
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        [1, "Jones", "777"],
                        [2, "Smith", "787"],
                        [3, "Johnson", "797"]))
        AssertEqual(db["pilots"],
                    MakeRelation(
                        ["name", "home"],
                        ["Jones", "New York"],
                        ["Smith", "Chicago"],
                        ["Johnson", "Seattle"]))

        let pilots = db["pilots"]
        _ = db.transaction({
            let pilots = $0["pilots"]
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
    
    func testSnapshotChangeNotification() {
        let sqliteDB = makeDB().db
        let db = ChangeLoggingDatabase(sqliteDB)
        let flightsScheme: Scheme = ["number", "pilot", "equipment"]
        let pilotsScheme: Scheme = ["name", "home"]
        
        _ = sqliteDB.createRelation("flights", scheme: flightsScheme)
        _ = sqliteDB.createRelation("pilots", scheme: pilotsScheme)
        
        var lastFlightsChange: RelationChange?
        _ = db["flights"].addChangeObserver({ lastFlightsChange = $0 })
        
        var lastPilotsChange: RelationChange?
        _ = db["pilots"].addChangeObserver({ lastPilotsChange = $0 })
        
        let s1 = db.takeSnapshot()
        
        _ = db.transaction({
            let flights = $0["flights"]
            let pilots = $0["pilots"]
            
            _ = flights.add(["number": 1, "pilot": "Jones", "equipment": "777"])
            _ = flights.add(["number": 2, "pilot": "Smith", "equipment": "787"])
            _ = flights.add(["number": 3, "pilot": "Johnson", "equipment": "797"])
            
            _ = pilots.add(["name": "Jones", "home": "New York"])
            _ = pilots.add(["name": "Smith", "home": "Chicago"])
            _ = pilots.add(["name": "Johnson", "home": "Seattle"])
        })
        
        let s2 = db.takeSnapshot()
        
        _ = db.transaction({
            let flights = $0["flights"]
            let pilots = $0["pilots"]
            
            _ = flights.add(["number": 4, "pilot": "Jones", "equipment": "DC-10"])
            _ = flights.update(Attribute("number") *== RelationValue(1 as Int64), newValues: ["pilot": "Smith"])
            _ = flights.delete(Attribute("equipment") *== "797")
            
            _ = pilots.add(["name": "Horton", "home": "Miami"])
            _ = pilots.update(Attribute("name") *== "Jones", newValues: ["home": "Boston"])
            _ = pilots.delete(Attribute("home") *== "Seattle")
        })
        
        let s3 = db.takeSnapshot()
        
        lastFlightsChange = nil
        lastPilotsChange = nil
        _ = db.restoreSnapshot(s2)
        AssertEqual(lastFlightsChange?.added,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        [1, "Jones", "777"],
                        [3, "Johnson", "797"]))
        AssertEqual(lastFlightsChange?.removed,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        [1, "Smith", "777"],
                        [4, "Jones", "DC-10"]))
        AssertEqual(lastPilotsChange?.added,
                    MakeRelation(
                        ["name", "home"],
                        ["Jones", "New York"],
                        ["Johnson", "Seattle"]))
        AssertEqual(lastPilotsChange?.removed,
                    MakeRelation(
                        ["name", "home"],
                        ["Jones", "Boston"],
                        ["Horton", "Miami"]))
        
        lastFlightsChange = nil
        lastPilotsChange = nil
        _ = db.restoreSnapshot(s1)
        AssertEqual(lastFlightsChange?.added, nil)
        AssertEqual(lastFlightsChange?.removed,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        [1, "Jones", "777"],
                        [2, "Smith", "787"],
                        [3, "Johnson", "797"]))
        AssertEqual(lastPilotsChange?.added, nil)
        AssertEqual(lastPilotsChange?.removed,
                    MakeRelation(
                        ["name", "home"],
                        ["Jones", "New York"],
                        ["Smith", "Chicago"],
                        ["Johnson", "Seattle"]))
        
        lastFlightsChange = nil
        lastPilotsChange = nil
        _ = db.restoreSnapshot(s2)
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
        
        lastFlightsChange = nil
        lastPilotsChange = nil
        _ = db.restoreSnapshot(s3)
        AssertEqual(lastFlightsChange?.added,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        [1, "Smith", "777"],
                        [4, "Jones", "DC-10"]))
        AssertEqual(lastFlightsChange?.removed,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        [1, "Jones", "777"],
                        [3, "Johnson", "797"]))
        AssertEqual(lastPilotsChange?.added,
                    MakeRelation(
                        ["name", "home"],
                        ["Jones", "Boston"],
                        ["Horton", "Miami"]))
        AssertEqual(lastPilotsChange?.removed,
                    MakeRelation(
                        ["name", "home"],
                        ["Jones", "New York"],
                        ["Johnson", "Seattle"]))
        
        lastFlightsChange = nil
        lastPilotsChange = nil
        _ = db.restoreSnapshot(s1)
        AssertEqual(lastFlightsChange?.added, nil)
        AssertEqual(lastFlightsChange?.removed,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        [1, "Smith", "777"],
                        [2, "Smith", "787"],
                        [4, "Jones", "DC-10"]))
        AssertEqual(lastPilotsChange?.added, nil)
        AssertEqual(lastPilotsChange?.removed,
                    MakeRelation(
                        ["name", "home"],
                        ["Jones", "Boston"],
                        ["Smith", "Chicago"],
                        ["Horton", "Miami"]))
        
        lastFlightsChange = nil
        lastPilotsChange = nil
        _ = db.restoreSnapshot(s3)
        AssertEqual(lastFlightsChange?.added,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        [1, "Smith", "777"],
                        [2, "Smith", "787"],
                        [4, "Jones", "DC-10"]))
        AssertEqual(lastFlightsChange?.removed, nil)
        AssertEqual(lastPilotsChange?.added,
                    MakeRelation(
                        ["name", "home"],
                        ["Jones", "Boston"],
                        ["Smith", "Chicago"],
                        ["Horton", "Miami"]))
        AssertEqual(lastPilotsChange?.removed, nil)
        
        lastFlightsChange = nil
        lastPilotsChange = nil
        _ = db.restoreSnapshot(s3)
        AssertEqual(lastFlightsChange?.added, nil)
        AssertEqual(lastFlightsChange?.removed, nil)
        AssertEqual(lastPilotsChange?.added, nil)
        AssertEqual(lastPilotsChange?.removed, nil)
    }
    
    func testLongLogSpeed() {
        let sqliteDB = makeDB().db
        let db = ChangeLoggingDatabase(sqliteDB)
        let flightsScheme: Scheme = ["number", "pilot", "equipment"]
        
        _ = sqliteDB.createRelation("flights", scheme: flightsScheme)
        
        let flights = db["flights"]
        
        _ = flights.add(["number": 1, "pilot": "Jones", "equipment": "777"])
        
        for i in 0..<100 {
            _ = flights.update(Attribute("number") *== 1, newValues: ["pilot": .text("Jones \(i)")])
            if i % 2 == 0 {
                _ = flights.add(["number": 2, "pilot": "Smith", "equipment": "787"])
            } else {
                _ = flights.delete(Attribute("number") *== 2)
            }
        }
        
        measure({
            for _ in flights.rows() {}
        })
    }
    
    func testLongLogSnapshotSpeed() {
        let sqliteDB = makeDB().db
        let db = ChangeLoggingDatabase(sqliteDB)
        let flightsScheme: Scheme = ["number", "pilot", "equipment"]
        
        _ = sqliteDB.createRelation("flights", scheme: flightsScheme)
        
        let flights = db["flights"]
        
        _ = flights.add(["number": 1, "pilot": "Jones", "equipment": "777"])
        
        for i in 0..<100 {
            _ = flights.update(Attribute("number") *== 1, newValues: ["pilot": .text("Jones \(i)")])
            if i % 2 == 0 {
                _ = flights.add(["number": 2, "pilot": "Smith", "equipment": "787"])
            } else {
                _ = flights.delete(Attribute("number") *== 2)
            }
        }
        
        let snapshot = db.takeSnapshot()
        _ = flights.add(["number": 3, "pilot": "Thompson", "equipment": "727"])
        let endSnapshot = db.takeSnapshot()
        
        measure({
            _ = db.restoreSnapshot(snapshot)
            _ = db.restoreSnapshot(endSnapshot)
        })
    }
    
    func testConcurrentIteration() {
        let underlying = MakeRelation(["a"])
        let r = ChangeLoggingRelation(baseRelation: underlying)
        
        for i: Int64 in 0..<10000 {
            _ = r.delete(Attribute("a") *== i - 1)
            _ = r.add(["a": .integer(i)])
            
            DispatchQueue.concurrentPerform(iterations: 2, execute: { _ in
                for row in r.rows() {
                    XCTAssertNil(row.err)
                }
            })
        }
    }
}
