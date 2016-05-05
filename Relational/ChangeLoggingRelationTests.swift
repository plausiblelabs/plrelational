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
        db.createRelation("flights", scheme: scheme)
        let table = db["flights", scheme]
        
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
            referenceRelation.update(terms, to: newValues)
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
            db["flights", scheme].add(row)
            referenceRelation.add(row)
        }
        
        func delete(terms: [ComparisonTerm]) {
            db["flights", scheme].delete(terms)
            referenceRelation.delete(terms)
        }
        
        func update(terms: [ComparisonTerm], _ newValues: Row) {
            db["flights", scheme].update(terms, newValues: newValues)
            referenceRelation.update(terms, to: newValues)
        }
        
        AssertEqual(db["flights", scheme],
                    MakeRelation(
                        ["number", "pilot", "equipment"]))
        AssertEqual(sqliteDB["flights", scheme],
                    MakeRelation(
                        ["number", "pilot", "equipment"]))
        
        XCTAssertNil(db.save().err)
        
        AssertEqual(db["flights", scheme],
                    MakeRelation(
                        ["number", "pilot", "equipment"]))
        AssertEqual(sqliteDB["flights", scheme],
                    MakeRelation(
                        ["number", "pilot", "equipment"]))
        
        add(["number": "1", "pilot": "Pat", "equipment": "A380"])
        add(["number": "2", "pilot": "Sam", "equipment": "A320"])
        add(["number": "3", "pilot": "Sue", "equipment": "A340"])
        
        AssertEqual(sqliteDB["flights", scheme],
                    MakeRelation(
                        ["number", "pilot", "equipment"]))
        AssertEqual(db["flights", scheme], referenceRelation)
        
        XCTAssertNil(db.save().err)
        
        AssertEqual(sqliteDB["flights", scheme], db["flights", scheme])
        AssertEqual(sqliteDB["flights", scheme], referenceRelation)
        
        add(["number": "4", "pilot": "Tim", "equipment": "A340"])
        delete([Attribute("equipment") *== "A340"])
        add(["number": "5", "pilot": "Ham", "equipment": "A340"])
        add(["number": "6", "pilot": "Ham", "equipment": "A340"])
        update([Attribute("pilot") *== "Ham"], ["pilot": "Stan"])
        add(["number": "7", "pilot": "Ham", "equipment": "A340"])
        delete([Attribute("pilot") *== "Ham"])
        add(["number": "7", "pilot": "Stan", "equipment": "A340"])
        
        AssertEqual(db["flights", scheme], referenceRelation)
        XCTAssertNil(db.save().err)
        AssertEqual(sqliteDB["flights", scheme], referenceRelation)
        AssertEqual(sqliteDB["flights", scheme], db["flights", scheme])
    }
}
