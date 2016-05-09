import XCTest
import libRelational

class ChangeLoggingRelationTests: DBTestCase {
    func testBare() {
        let underlying = MakeRelation(
            ["number", "pilot", "equipment"],
            ["123",    "Jones", "707"],
            ["124",    "Steve", "727"],
            ["125",    "Martha", "747"],
            ["126",    "Alice", "767"],
            ["127",    "Wendy", "707"]
        )
        
        let loggingRelation = ChangeLoggingRelation(underlyingRelation: underlying)
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
        
        let loggingRelation = ChangeLoggingRelation(underlyingRelation: underlying)
        
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
    
    func testDelete() {
        let underlying = MakeRelation(
            ["number", "pilot", "equipment"],
            ["123",    "Jones", "707"],
            ["124",    "Steve", "727"],
            ["125",    "Martha", "747"],
            ["126",    "Alice", "767"],
            ["127",    "Wendy", "707"]
        )
        
        let loggingRelation = ChangeLoggingRelation(underlyingRelation: underlying)
        
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
        
        loggingRelation.delete([Attribute("number") *== "42"])
        AssertEqual(loggingRelation,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["123",    "Jones", "707"],
                        ["124",    "Steve", "727"],
                        ["125",    "Martha", "747"],
                        ["126",    "Alice", "767"],
                        ["127",    "Wendy", "707"]
            ))
        
        loggingRelation.delete([Attribute("number") *== "123"])
        AssertEqual(loggingRelation,
                    MakeRelation(
                        ["number", "pilot", "equipment"],
                        ["124",    "Steve", "727"],
                        ["125",    "Martha", "747"],
                        ["126",    "Alice", "767"],
                        ["127",    "Wendy", "707"]
            ))
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
        
        let loggingRelation = ChangeLoggingRelation(underlyingRelation: underlying)
        
        loggingRelation.add(["number": "42", "pilot": "Adams", "equipment": "MD-11"])
        loggingRelation.update([Attribute("number") *== "42"], newValues: ["equipment": "DC-10"])
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
        
        loggingRelation.update([Attribute("number") *== "123"], newValues: ["equipment": "DC-10"])
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
        
        loggingRelation.update([Attribute("equipment") *== "DC-10"], newValues: ["pilot": "JFK"])
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
    
    func testSave() {
        let db = makeDB().db.sqliteDatabase
        let scheme: Scheme = ["number", "pilot", "equipment"]
        let table = db.getOrCreateRelation("flights", scheme: scheme).ok!
        
        let loggingRelation = ChangeLoggingRelation(underlyingRelation: table)
        var referenceRelation = ConcreteRelation(scheme: scheme)
        
        func add(row: Row) {
            loggingRelation.add(row)
            referenceRelation.add(row)
        }
        
        func delete(terms: [ComparisonTerm]) {
            loggingRelation.delete(terms)
            referenceRelation.delete(terms)
        }
        
        func update(terms: [ComparisonTerm], _ newValues: Row) {
            loggingRelation.update(terms, newValues: newValues)
            referenceRelation.update(terms, newValues: newValues)
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
        delete([Attribute("equipment") *== "A340"])
        add(["number": "5", "pilot": "Ham", "equipment": "A340"])
        add(["number": "6", "pilot": "Ham", "equipment": "A340"])
        update([Attribute("pilot") *== "Ham"], ["pilot": "Stan"])
        add(["number": "7", "pilot": "Ham", "equipment": "A340"])
        delete([Attribute("pilot") *== "Ham"])
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
        db.createRelation("flights", scheme: scheme)
        
        var referenceRelation = ConcreteRelation(scheme: scheme)
        
        func add(row: Row) {
            db.transaction({
                $0["flights"].add(row)
            })
            referenceRelation.add(row)
        }
        
        func delete(terms: [ComparisonTerm]) {
            db.transaction({
                $0["flights"].delete(terms)
            })
            referenceRelation.delete(terms)
        }
        
        func update(terms: [ComparisonTerm], _ newValues: Row) {
            db.transaction({
                $0["flights"].update(terms, newValues: newValues)
            })
            referenceRelation.update(terms, newValues: newValues)
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
        delete([Attribute("equipment") *== "A340"])
        add(["number": "5", "pilot": "Ham", "equipment": "A340"])
        add(["number": "6", "pilot": "Ham", "equipment": "A340"])
        update([Attribute("pilot") *== "Ham"], ["pilot": "Stan"])
        add(["number": "7", "pilot": "Ham", "equipment": "A340"])
        delete([Attribute("pilot") *== "Ham"])
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
        
        db.createRelation("flights", scheme: flightsScheme)
        db.createRelation("pilots", scheme: pilotsScheme)
        
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
            flights.update([Attribute("number") *== RelationValue(1 as Int64)], newValues: ["pilot": "Smith"])
            flights.delete([Attribute("equipment") *== "797"])
            
            pilots.add(["name": "Horton", "home": "Miami"])
            pilots.update([Attribute("name") *== "Jones"], newValues: ["home": "Boston"])
            pilots.delete([Attribute("home") *== "Seattle"])
            
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
}
