import XCTest
import libRelational

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
        
        loggingRelation.add(["number": "42", "pilot": "Adams", "equipment": "MD-11"])
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
        
        loggingRelation.add(["number": "43", "pilot": "Adams", "equipment": "MD-11"])
        loggingRelation.add(["number": "44", "pilot": "Adams", "equipment": "MD-11"])
        loggingRelation.add(["number": "45", "pilot": "Adams", "equipment": "MD-11"])
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
        
        loggingRelation.add(["number": "42", "pilot": "Adams", "equipment": "MD-11"])
        AssertEqual(lastChange!.added!,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["42",     "Adams", "MD-11"]))
        AssertEqual(lastChange!.removed, nil)
        
        loggingRelation.add(["number": "43", "pilot": "Adams", "equipment": "MD-11"])
        AssertEqual(lastChange!.added!,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["43",     "Adams", "MD-11"]))
        AssertEqual(lastChange!.removed, nil)
        
        loggingRelation.add(["number": "44", "pilot": "Adams", "equipment": "MD-11"])
        AssertEqual(lastChange!.added!,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["44",     "Adams", "MD-11"]))
        AssertEqual(lastChange!.removed, nil)
        
        loggingRelation.add(["number": "45", "pilot": "Adams", "equipment": "MD-11"])
        AssertEqual(lastChange!.added!,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["45",     "Adams", "MD-11"]))
        AssertEqual(lastChange!.removed, nil)
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
        
        loggingRelation.add(["number": "42", "pilot": "Adams", "equipment": "MD-11"])
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
        
        loggingRelation.delete(Attribute("number") *== "42")
        AssertEqual(loggingRelation,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["123",    "Jones", "707"],
                        ["124",    "Steve", "727"],
                        ["125",    "Martha", "747"],
                        ["126",    "Alice", "767"],
                        ["127",    "Wendy", "707"]
            ))
        
        loggingRelation.delete(Attribute("number") *== "123")
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
        
        loggingRelation.add(["number": "42", "pilot": "Adams", "equipment": "MD-11"])
        
        loggingRelation.delete(Attribute("number") *== "42")
        AssertEqual(lastChange!.removed!,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["42",     "Adams", "MD-11"]))
        AssertEqual(lastChange!.added, nil)
        
        
        loggingRelation.delete(Attribute("number") *== "123")
        AssertEqual(lastChange!.removed!,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["123",    "Jones", "707"]))
        AssertEqual(lastChange!.added, nil)
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
        
        loggingRelation.add(["number": "42", "pilot": "Adams", "equipment": "MD-11"])
        loggingRelation.update(Attribute("number") *== "42", newValues: ["equipment": "DC-10"])
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
        
        loggingRelation.update(Attribute("number") *== "123", newValues: ["equipment": "DC-10"])
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
        
        loggingRelation.update(Attribute("equipment") *== "DC-10", newValues: ["pilot": "JFK"])
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
        
        loggingRelation.add(["number": "42", "pilot": "Adams", "equipment": "MD-11"])
        loggingRelation.update(Attribute("number") *== "42", newValues: ["equipment": "DC-10"])
        AssertEqual(lastChange!.removed!,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["42",     "Adams", "MD-11"]))
        AssertEqual(lastChange!.added!,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["42",     "Adams", "DC-10"]))
        
        loggingRelation.update(Attribute("number") *== "123", newValues: ["equipment": "DC-10"])
        AssertEqual(lastChange!.removed!,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["123",    "Jones", "707"]))
        AssertEqual(lastChange!.added!,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["123",    "Jones", "DC-10"]))
        
        loggingRelation.update(Attribute("equipment") *== "DC-10", newValues: ["pilot": "JFK"])
        AssertEqual(lastChange!.removed!,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["42",     "Adams", "DC-10"],
                        ["123",    "Jones", "DC-10"]))
        AssertEqual(lastChange!.added!,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["42",     "JFK", "DC-10"],
                        ["123",    "JFK", "DC-10"]))
    }
    
    func testSave() {
        let db = makeDB().db.sqliteDatabase
        let scheme: Scheme = ["number", "pilot", "equipment"]
        let table = db.getOrCreateRelation("flights", scheme: scheme).ok!
        
        let loggingRelation = ChangeLoggingRelation(baseRelation: table)
        var referenceRelation = ConcreteRelation(scheme: scheme)
        
        func add(row: Row) {
            loggingRelation.add(row)
            referenceRelation.add(row)
        }
        
        func delete(query: SelectExpression) {
            loggingRelation.delete(query)
            referenceRelation.delete(query)
        }
        
        func update(query: SelectExpression, _ newValues: Row) {
            loggingRelation.update(query, newValues: newValues)
            referenceRelation.update(query, newValues: newValues)
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
    
    func testDatabase() {
        let sqliteDB = makeDB().db.sqliteDatabase
        let db = ChangeLoggingDatabase(sqliteDB)
        let scheme: Scheme = ["number", "pilot", "equipment"]
        sqliteDB.createRelation("flights", scheme: scheme)
        
        var referenceRelation = ConcreteRelation(scheme: scheme)
        
        func add(row: Row) {
            db.transaction({
                $0["flights"].add(row)
            })
            referenceRelation.add(row)
        }
        
        func delete(query: SelectExpression) {
            db.transaction({
                $0["flights"].delete(query)
            })
            referenceRelation.delete(query)
        }
        
        func update(query: SelectExpression, _ newValues: Row) {
            db.transaction({
                $0["flights"].update(query, newValues: newValues)
            })
            referenceRelation.update(query, newValues: newValues)
        }
        
        AssertEqual(db["flights"],
                    MakeRelation(
                        ["number", "pilot", "equipment"]))
        AssertEqual(sqliteDB["flights"]!,
                    MakeRelation(
                        ["number", "pilot", "equipment"]))
        
        XCTAssertNil(db.save().err)
        
        AssertEqual(db["flights"],
                    MakeRelation(
                        ["number", "pilot", "equipment"]))
        AssertEqual(sqliteDB["flights"]!,
                    MakeRelation(
                        ["number", "pilot", "equipment"]))
        
        add(["number": "1", "pilot": "Pat", "equipment": "A380"])
        add(["number": "2", "pilot": "Sam", "equipment": "A320"])
        add(["number": "3", "pilot": "Sue", "equipment": "A340"])
        
        AssertEqual(sqliteDB["flights"]!,
                    MakeRelation(
                        ["number", "pilot", "equipment"]))
        AssertEqual(db["flights"], referenceRelation)
        
        XCTAssertNil(db.save().err)
        
        AssertEqual(sqliteDB["flights"]!, db["flights"])
        AssertEqual(sqliteDB["flights"]!, referenceRelation)
        
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
        AssertEqual(sqliteDB["flights"]!, referenceRelation)
        AssertEqual(sqliteDB["flights"]!, db["flights"])
    }
    
    func testTransactions() {
        let sqliteDB = makeDB().db.sqliteDatabase
        let db = ChangeLoggingDatabase(sqliteDB)
        let flightsScheme: Scheme = ["number", "pilot", "equipment"]
        let pilotsScheme: Scheme = ["name", "home"]
        
        sqliteDB.createRelation("flights", scheme: flightsScheme)
        sqliteDB.createRelation("pilots", scheme: pilotsScheme)
        
        db.transaction({
            let flights = $0["flights"]
            let pilots = $0["pilots"]
            
            flights.add(["number": 1, "pilot": "Jones", "equipment": "777"])
            flights.add(["number": 2, "pilot": "Smith", "equipment": "787"])
            flights.add(["number": 3, "pilot": "Johnson", "equipment": "797"])
            
            pilots.add(["name": "Jones", "home": "New York"])
            pilots.add(["name": "Smith", "home": "Chicago"])
            pilots.add(["name": "Johnson", "home": "Seattle"])
            
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
        
        // And finally the SQLite database should change too
        AssertEqual(sqliteDB["flights"]!,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        [1, "Jones", "777"],
                        [2, "Smith", "787"],
                        [3, "Johnson", "797"]))
        AssertEqual(sqliteDB["pilots"]!,
                    MakeRelation(
                        ["name", "home"],
                        ["Jones", "New York"],
                        ["Smith", "Chicago"],
                        ["Johnson", "Seattle"]))
        
        db.transaction({
            let flights = $0["flights"]
            let pilots = $0["pilots"]
            
            flights.add(["number": 4, "pilot": "Jones", "equipment": "DC-10"])
            flights.update(Attribute("number") *== RelationValue(1 as Int64), newValues: ["pilot": "Smith"])
            flights.delete(Attribute("equipment") *== "797")
            
            pilots.add(["name": "Horton", "home": "Miami"])
            pilots.update(Attribute("name") *== "Jones", newValues: ["home": "Boston"])
            pilots.delete(Attribute("home") *== "Seattle")
            
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
        
        // And the SQLite databate should still have the old data
        AssertEqual(sqliteDB["flights"]!,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        [1, "Jones", "777"],
                        [2, "Smith", "787"],
                        [3, "Johnson", "797"]))
        AssertEqual(sqliteDB["pilots"]!,
                    MakeRelation(
                        ["name", "home"],
                        ["Jones", "New York"],
                        ["Smith", "Chicago"],
                        ["Johnson", "Seattle"]))
        
        XCTAssertNil(db.save().err)
        
        // Finally, the SQLite database should have the new data after saving
        AssertEqual(sqliteDB["flights"]!,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        [1, "Smith", "777"],
                        [2, "Smith", "787"],
                        [4, "Jones", "DC-10"]))
        AssertEqual(sqliteDB["pilots"]!,
                    MakeRelation(
                        ["name", "home"],
                        ["Jones", "Boston"],
                        ["Smith", "Chicago"],
                        ["Horton", "Miami"]))
    }
    
    func testTransactionNotifications() {
        let sqliteDB = makeDB().db.sqliteDatabase
        let db = ChangeLoggingDatabase(sqliteDB)
        let flightsScheme: Scheme = ["number", "pilot", "equipment"]
        let pilotsScheme: Scheme = ["name", "home"]
        
        sqliteDB.createRelation("flights", scheme: flightsScheme)
        sqliteDB.createRelation("pilots", scheme: pilotsScheme)
        
        var lastFlightsChange: RelationChange?
        _ = db["flights"].addChangeObserver({ lastFlightsChange = $0 })
        
        var lastPilotsChange: RelationChange?
        _ = db["pilots"].addChangeObserver({ lastPilotsChange = $0 })
        
        db.transaction({
            let flights = $0["flights"]
            let pilots = $0["pilots"]
            
            flights.add(["number": 1, "pilot": "Jones", "equipment": "777"])
            flights.add(["number": 2, "pilot": "Smith", "equipment": "787"])
            flights.add(["number": 3, "pilot": "Johnson", "equipment": "797"])
            
            pilots.add(["name": "Jones", "home": "New York"])
            pilots.add(["name": "Smith", "home": "Chicago"])
            pilots.add(["name": "Johnson", "home": "Seattle"])
        })
        
        AssertEqual(lastFlightsChange!.added!,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        [1, "Jones", "777"],
                        [2, "Smith", "787"],
                        [3, "Johnson", "797"]))
        XCTAssertTrue(lastFlightsChange!.removed!.isEmpty.ok!)
        AssertEqual(lastPilotsChange!.added!,
                    MakeRelation(
                        ["name", "home"],
                        ["Jones", "New York"],
                        ["Smith", "Chicago"],
                        ["Johnson", "Seattle"]))
        XCTAssertTrue(lastPilotsChange!.removed!.isEmpty.ok!)
        
        db.transaction({
            let flights = $0["flights"]
            let pilots = $0["pilots"]
            
            flights.add(["number": 4, "pilot": "Jones", "equipment": "DC-10"])
            flights.update(Attribute("number") *== RelationValue(1 as Int64), newValues: ["pilot": "Smith"])
            flights.delete(Attribute("equipment") *== "797")
            
            pilots.add(["name": "Horton", "home": "Miami"])
            pilots.update(Attribute("name") *== "Jones", newValues: ["home": "Boston"])
            pilots.delete(Attribute("home") *== "Seattle")
        })
        
        AssertEqual(lastFlightsChange!.added!,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        [4, "Jones", "DC-10"],
                        [1, "Smith", "777"]))
        AssertEqual(lastFlightsChange!.removed!,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        [3, "Johnson", "797"],
                        [1, "Jones", "777"]))
        AssertEqual(lastPilotsChange!.added!,
                    MakeRelation(
                        ["name", "home"],
                        ["Horton", "Miami"],
                        ["Jones", "Boston"]))
        AssertEqual(lastPilotsChange!.removed!,
                    MakeRelation(
                        ["name", "home"],
                        ["Jones", "New York"],
                        ["Johnson", "Seattle"]))
    }
    
    func testSnapshots() {
        let sqliteDB = makeDB().db.sqliteDatabase
        let db = ChangeLoggingDatabase(sqliteDB)
        let flightsScheme: Scheme = ["number", "pilot", "equipment"]
        let pilotsScheme: Scheme = ["name", "home"]
        
        sqliteDB.createRelation("flights", scheme: flightsScheme)
        sqliteDB.createRelation("pilots", scheme: pilotsScheme)
        
        var snapshots: [(ChangeLoggingDatabaseSnapshot, Relation, Relation)] = []
        
        snapshots.append((db.takeSnapshot(), MakeRelation(["number", "pilot", "equipment"]), MakeRelation(["name", "home"])))
        
        db.transaction({
            let flights = $0["flights"]
            let pilots = $0["pilots"]
            
            flights.add(["number": 1, "pilot": "Jones", "equipment": "777"])
            flights.add(["number": 2, "pilot": "Smith", "equipment": "787"])
            flights.add(["number": 3, "pilot": "Johnson", "equipment": "797"])
            
            pilots.add(["name": "Jones", "home": "New York"])
            pilots.add(["name": "Smith", "home": "Chicago"])
            pilots.add(["name": "Johnson", "home": "Seattle"])
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
        
        
        db.transaction({
            let flights = $0["flights"]
            let pilots = $0["pilots"]
            
            flights.add(["number": 4, "pilot": "Jones", "equipment": "DC-10"])
            flights.update(Attribute("number") *== RelationValue(1 as Int64), newValues: ["pilot": "Smith"])
            flights.delete(Attribute("equipment") *== "797")
            
            pilots.add(["name": "Horton", "home": "Miami"])
            pilots.update(Attribute("name") *== "Jones", newValues: ["home": "Boston"])
            pilots.delete(Attribute("home") *== "Seattle")
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
        
        for (snapshot, flights, pilots) in snapshots + snapshots.reverse() {
            db.restoreSnapshot(snapshot)
            AssertEqual(db["flights"], flights)
            AssertEqual(db["pilots"], pilots)
        }
    }
    
    func testTransactionSnapshots() {
        let sqliteDB = makeDB().db.sqliteDatabase
        let db = ChangeLoggingDatabase(sqliteDB)
        let flightsScheme: Scheme = ["number", "pilot", "equipment"]
        let pilotsScheme: Scheme = ["name", "home"]
        
        sqliteDB.createRelation("flights", scheme: flightsScheme)
        sqliteDB.createRelation("pilots", scheme: pilotsScheme)
        
        let (before, after) = db.transactionWithSnapshots({
            let flights = $0["flights"]
            let pilots = $0["pilots"]
            
            flights.add(["number": 1, "pilot": "Jones", "equipment": "777"])
            flights.add(["number": 2, "pilot": "Smith", "equipment": "787"])
            flights.add(["number": 3, "pilot": "Johnson", "equipment": "797"])
            
            pilots.add(["name": "Jones", "home": "New York"])
            pilots.add(["name": "Smith", "home": "Chicago"])
            pilots.add(["name": "Johnson", "home": "Seattle"])
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
        
        db.restoreSnapshot(before)
        
        AssertEqual(db["flights"],
                    MakeRelation(
                        ["number", "pilot", "equipment"]))
        AssertEqual(db["pilots"],
                    MakeRelation(
                        ["name", "home"]))
        
        db.restoreSnapshot(after)
        
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
        db.transaction({
            let pilots = $0["pilots"]
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
    
    func testSnapshotChangeNotification() {
        let sqliteDB = makeDB().db.sqliteDatabase
        let db = ChangeLoggingDatabase(sqliteDB)
        let flightsScheme: Scheme = ["number", "pilot", "equipment"]
        let pilotsScheme: Scheme = ["name", "home"]
        
        sqliteDB.createRelation("flights", scheme: flightsScheme)
        sqliteDB.createRelation("pilots", scheme: pilotsScheme)
        
        var lastFlightsChange: RelationChange?
        _ = db["flights"].addChangeObserver({ lastFlightsChange = $0 })
        
        var lastPilotsChange: RelationChange?
        _ = db["pilots"].addChangeObserver({ lastPilotsChange = $0 })
        
        let s1 = db.takeSnapshot()
        
        db.transaction({
            let flights = $0["flights"]
            let pilots = $0["pilots"]
            
            flights.add(["number": 1, "pilot": "Jones", "equipment": "777"])
            flights.add(["number": 2, "pilot": "Smith", "equipment": "787"])
            flights.add(["number": 3, "pilot": "Johnson", "equipment": "797"])
            
            pilots.add(["name": "Jones", "home": "New York"])
            pilots.add(["name": "Smith", "home": "Chicago"])
            pilots.add(["name": "Johnson", "home": "Seattle"])
        })
        
        let s2 = db.takeSnapshot()
        
        db.transaction({
            let flights = $0["flights"]
            let pilots = $0["pilots"]
            
            flights.add(["number": 4, "pilot": "Jones", "equipment": "DC-10"])
            flights.update(Attribute("number") *== RelationValue(1 as Int64), newValues: ["pilot": "Smith"])
            flights.delete(Attribute("equipment") *== "797")
            
            pilots.add(["name": "Horton", "home": "Miami"])
            pilots.update(Attribute("name") *== "Jones", newValues: ["home": "Boston"])
            pilots.delete(Attribute("home") *== "Seattle")
        })
        
        let s3 = db.takeSnapshot()
        
        lastFlightsChange = nil
        lastPilotsChange = nil
        db.restoreSnapshot(s2)
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
        db.restoreSnapshot(s1)
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
        db.restoreSnapshot(s2)
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
        db.restoreSnapshot(s3)
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
        db.restoreSnapshot(s1)
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
        db.restoreSnapshot(s3)
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
        db.restoreSnapshot(s3)
        AssertEqual(lastFlightsChange?.added, nil)
        AssertEqual(lastFlightsChange?.removed, nil)
        AssertEqual(lastPilotsChange?.added, nil)
        AssertEqual(lastPilotsChange?.removed, nil)
    }
    
    func testLongLogSpeed() {
        let sqliteDB = makeDB().db.sqliteDatabase
        let db = ChangeLoggingDatabase(sqliteDB)
        let flightsScheme: Scheme = ["number", "pilot", "equipment"]
        
        sqliteDB.createRelation("flights", scheme: flightsScheme)
        
        let flights = db["flights"]
        
        flights.add(["number": 1, "pilot": "Jones", "equipment": "777"])
        
        for i in 0..<100 {
            flights.update(Attribute("number") *== 1, newValues: ["pilot": .Text("Jones \(i)")])
            if i % 2 == 0 {
                flights.add(["number": 2, "pilot": "Smith", "equipment": "787"])
            } else {
                flights.delete(Attribute("number") *== 2)
            }
        }
        
        measureBlock({
            for _ in flights.rows() {}
        })
    }
    
    func testLongLogSnapshotSpeed() {
        let sqliteDB = makeDB().db.sqliteDatabase
        let db = ChangeLoggingDatabase(sqliteDB)
        let flightsScheme: Scheme = ["number", "pilot", "equipment"]
        
        sqliteDB.createRelation("flights", scheme: flightsScheme)
        
        let flights = db["flights"]
        
        flights.add(["number": 1, "pilot": "Jones", "equipment": "777"])
        
        for i in 0..<100 {
            flights.update(Attribute("number") *== 1, newValues: ["pilot": .Text("Jones \(i)")])
            if i % 2 == 0 {
                flights.add(["number": 2, "pilot": "Smith", "equipment": "787"])
            } else {
                flights.delete(Attribute("number") *== 2)
            }
        }
        
        let snapshot = db.takeSnapshot()
        flights.add(["number": 3, "pilot": "Thompson", "equipment": "727"])
        let endSnapshot = db.takeSnapshot()
        
        measureBlock({
            db.restoreSnapshot(snapshot)
            db.restoreSnapshot(endSnapshot)
        })
    }
}
