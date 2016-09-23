//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import libRelational
import sqlite3

class SQLiteDatabaseTests: DBTestCase {
    func makeSQLRelation(_ name: String, _ attributes: [Attribute], _ rowValues: [RelationValue]...) -> SQLiteTableRelation {
        let db = makeDB().db
        
        let scheme = Scheme(attributes: Set(attributes))
        let rows = rowValues.map({ values -> Row in
            precondition(values.count == attributes.count)
            return Row(values: Dictionary(zip(attributes, values)))
        })
        
        let relation = db.createRelation(name, scheme: scheme).ok!
        for row in rows {
            XCTAssertNil(relation.add(row).err)
        }
        return relation
    }
    
    func testSQLiteBasics() {
        let db = makeDB().db
        _ = db.createRelation("FLIGHTS", scheme: ["NUMBER", "FROM", "TO"])
        _ = db.createRelation("FLIGHTS", scheme: ["NUMBER", "FROM", "TO"])
        
        let FLIGHTS = db["FLIGHTS"]!
        _ = FLIGHTS.add(["NUMBER": "123", "FROM": "JFK", "TO": "Unknown"])
        _ = FLIGHTS.add(["NUMBER": "124", "FROM": "JFK", "TO": "A"])
        _ = FLIGHTS.add(["NUMBER": "125", "FROM": "JFK", "TO": "B"])
        _ = FLIGHTS.add(["NUMBER": "126", "FROM": "JFK", "TO": "C"])
        _ = FLIGHTS.add(["NUMBER": "127", "FROM": "JFK", "TO": "D"])
        _ = FLIGHTS.add(["NUMBER": "128", "FROM": "JFK", "TO": "A"])
        _ = FLIGHTS.add(["NUMBER": "129", "FROM": "JFK", "TO": "A"])
        _ = FLIGHTS.add(["NUMBER": "888", "FROM": "Here", "TO": "There"])
        _ = FLIGHTS.add(["NUMBER": "3", "FROM": "Atlanta", "TO": "Atlanta"])
        
        AssertEqual(FLIGHTS,
                    MakeRelation(
                        ["FROM",     "NUMBER", "TO"],
                        ["JFK",      "123",    "Unknown"],
                        ["JFK",      "124",    "A"],
                        ["JFK",      "125",    "B"],
                        ["JFK",      "126",    "C"],
                        ["JFK",      "127",    "D"],
                        ["JFK",      "128",    "A"],
                        ["JFK",      "129",    "A"],
                        ["Here",     "888",    "There"],
                        ["Atlanta",  "3",      "Atlanta"]))
        
        AssertEqual(FLIGHTS.select(SelectExpressionBinaryOperator(lhs: Attribute("NUMBER"), op: LTComparator(), rhs: "125")),
                    MakeRelation(
                        ["FROM",     "NUMBER", "TO"],
                        ["JFK",      "123",    "Unknown"],
                        ["JFK",      "124",    "A"]))
        AssertEqual(FLIGHTS.select(["FROM": "JFK"]),
                    MakeRelation(
                        ["FROM",     "NUMBER", "TO"],
                        ["JFK",      "123",    "Unknown"],
                        ["JFK",      "124",    "A"],
                        ["JFK",      "125",    "B"],
                        ["JFK",      "126",    "C"],
                        ["JFK",      "127",    "D"],
                        ["JFK",      "128",    "A"],
                        ["JFK",      "129",    "A"]))
        AssertEqual(FLIGHTS.select(["FROM": "JFK"]).select(["TO": "A"]),
                    MakeRelation(
                        ["FROM",     "NUMBER", "TO"],
                        ["JFK",      "124",    "A"],
                        ["JFK",      "128",    "A"],
                        ["JFK",      "129",    "A"]))
        
        _ = FLIGHTS.update(Attribute("NUMBER") *== "888", newValues: ["FROM": "Tennessee", "TO": "Spotsylvania"])
        AssertEqual(FLIGHTS,
                    MakeRelation(
                        ["FROM",     "NUMBER", "TO"],
                        ["JFK",      "123",    "Unknown"],
                        ["JFK",      "124",    "A"],
                        ["JFK",      "125",    "B"],
                        ["JFK",      "126",    "C"],
                        ["JFK",      "127",    "D"],
                        ["JFK",      "128",    "A"],
                        ["JFK",      "129",    "A"],
                        ["Tennessee","888",    "Spotsylvania"],
                        ["Atlanta",  "3",      "Atlanta"]))
        
        _ = FLIGHTS.delete(Attribute("FROM") *== "JFK")
        AssertEqual(FLIGHTS,
                    MakeRelation(
                        ["FROM",     "NUMBER", "TO"],
                        ["Tennessee","888",    "Spotsylvania"],
                        ["Atlanta",  "3",      "Atlanta"]))
    }
    
    func testCommittedTransaction() {
        let db = makeDB().db
        _ = db.createRelation("FLIGHTS", scheme: ["NUMBER", "FROM", "TO"])
        
        _ = db.transaction({
            let FLIGHTS = db["FLIGHTS"]!
            _ = FLIGHTS.add(["NUMBER": "123", "FROM": "JFK", "TO": "Unknown"])
            _ = FLIGHTS.add(["NUMBER": "124", "FROM": "JFK", "TO": "A"])
            _ = FLIGHTS.add(["NUMBER": "125", "FROM": "JFK", "TO": "B"])
            _ = FLIGHTS.add(["NUMBER": "126", "FROM": "JFK", "TO": "C"])
            _ = FLIGHTS.add(["NUMBER": "127", "FROM": "JFK", "TO": "D"])
            _ = FLIGHTS.add(["NUMBER": "128", "FROM": "JFK", "TO": "A"])
            _ = FLIGHTS.add(["NUMBER": "129", "FROM": "JFK", "TO": "A"])
            _ = FLIGHTS.add(["NUMBER": "888", "FROM": "Here", "TO": "There"])
            _ = FLIGHTS.add(["NUMBER": "3", "FROM": "Atlanta", "TO": "Atlanta"])
            return .commit
        })
        
        AssertEqual(db["FLIGHTS"]!,
                    MakeRelation(
                        ["FROM",     "NUMBER", "TO"],
                        ["JFK",      "123",    "Unknown"],
                        ["JFK",      "124",    "A"],
                        ["JFK",      "125",    "B"],
                        ["JFK",      "126",    "C"],
                        ["JFK",      "127",    "D"],
                        ["JFK",      "128",    "A"],
                        ["JFK",      "129",    "A"],
                        ["Here",     "888",    "There"],
                        ["Atlanta",  "3",      "Atlanta"]))
    }
    
    func testRolledBackTransaction() {
        let db = makeDB().db
        _ = db.createRelation("FLIGHTS", scheme: ["NUMBER", "FROM", "TO"])
        
        _ = db.transaction({
            let FLIGHTS = db["FLIGHTS"]!
            _ = FLIGHTS.add(["NUMBER": "123", "FROM": "JFK", "TO": "Unknown"])
            _ = FLIGHTS.add(["NUMBER": "124", "FROM": "JFK", "TO": "A"])
            _ = FLIGHTS.add(["NUMBER": "125", "FROM": "JFK", "TO": "B"])
            _ = FLIGHTS.add(["NUMBER": "126", "FROM": "JFK", "TO": "C"])
            _ = FLIGHTS.add(["NUMBER": "127", "FROM": "JFK", "TO": "D"])
            _ = FLIGHTS.add(["NUMBER": "128", "FROM": "JFK", "TO": "A"])
            _ = FLIGHTS.add(["NUMBER": "129", "FROM": "JFK", "TO": "A"])
            _ = FLIGHTS.add(["NUMBER": "888", "FROM": "Here", "TO": "There"])
            _ = FLIGHTS.add(["NUMBER": "3", "FROM": "Atlanta", "TO": "Atlanta"])
            return .rollback
        })
        
        AssertEqual(db["FLIGHTS"]!,
                    MakeRelation(
                        ["FROM", "NUMBER", "TO"]))
    }
    
    func testBasicObservation() {
        let db = makeDB().db
        
        XCTAssertNil(db.createRelation("test", scheme: ["column"]).err)
        let r = db["test"]!
        
        var changeCount = 0
        let removal = r.addChangeObserver({ _ in changeCount += 1 })
        
        _ = r.add(["column": "42"])
        XCTAssertEqual(changeCount, 1)
        
        _ = r.update(Attribute("column") *== "42", newValues: ["column": "43"])
        XCTAssertEqual(changeCount, 2)
        
        _ = r.delete(Attribute("column") *== "43")
        XCTAssertEqual(changeCount, 3)
        
        removal()
        _ = r.add(["column": "123"])
        XCTAssertEqual(changeCount, 3)
    }
    
    func testJoinObservation() {
        let db = makeDB().db
        
        XCTAssertNil(db.createRelation("a", scheme: ["1", "2"]).err)
        XCTAssertNil(db.createRelation("b", scheme: ["2", "3"]).err)
        
        let a = db["a"]!
        let b = db["b"]!
        
        _ = a.add(["1": "X", "2": "X"])
        _ = a.add(["1": "X", "2": "Y"])
        _ = a.add(["1": "Y", "2": "Z"])
        
        _ = b.add(["2": "X", "3": "X"])
        _ = b.add(["2": "X", "3": "Y"])
        _ = b.add(["2": "Y", "3": "Z"])
        
        let joined = a.join(b)
        AssertEqual(joined,
                    MakeRelation(
                        ["1", "2", "3"],
                        ["X", "X", "X"],
                        ["X", "X", "Y"],
                        ["X", "Y", "Z"]))
        
        var changed = false
        let removal = joined.addChangeObserver({ _ in changed = true })
        
        changed = false
        _ = a.delete(Attribute("2") *== "Y")
        XCTAssertTrue(changed)
        AssertEqual(joined,
                    MakeRelation(
                        ["1", "2", "3"],
                        ["X", "X", "X"],
                        ["X", "X", "Y"]))
        
        changed = false
        _ = b.add(["2": "Z", "3": "Z"])
        XCTAssertTrue(changed)
        AssertEqual(joined,
                    MakeRelation(
                        ["1", "2", "3"],
                        ["X", "X", "X"],
                        ["X", "X", "Y"],
                        ["Y", "Z", "Z"]))
        
        removal()
        changed = false
        _ = a.delete(Attribute("1") *== "X")
        XCTAssertFalse(changed)
    }
    
    func testUpdates() {
        let db = makeDB().db
        
        let peopleScheme: Scheme = ["id", "name", "houseID"]
        XCTAssertNil(db.createRelation("people", scheme: peopleScheme).err)
        
        let housesScheme: Scheme = ["id", "address"]
        XCTAssertNil(db.createRelation("houses", scheme: housesScheme).err)
        
        let people = db["people"]!
        let houses = db["houses"]!
        
        XCTAssertNil(people.add(["id": 1, "name": "Johnson", "houseID": 1]).err)
        XCTAssertNil(people.add(["id": 2, "name": "Stanley", "houseID": 2]).err)
        XCTAssertNil(people.add(["id": 3, "name": "Jones", "houseID": 2]).err)
        
        XCTAssertNil(houses.add(["id": 1, "address": "123 Main St."]).err)
        XCTAssertNil(houses.add(["id": 2, "address": "456 West St."]).err)
        
        var joined = people.equijoin(houses.renameAttributes(["id": "renamed_house_id"]), matching: ["houseID": "renamed_house_id"])
        XCTAssertNil(joined.update(Attribute("id") *== RelationValue(1 as Int64), newValues: ["name": "Stevens"]).err)
        XCTAssertNil(joined.update(Attribute("id") *== RelationValue(2 as Int64), newValues: ["address": "999 Something Ln."]).err)
        
        AssertEqual(joined,
                    MakeRelation(
                        ["id", "name", "houseID", "renamed_house_id", "address"],
                        [1, "Stevens", 1, 1, "123 Main St."],
                        [2, "Stanley", 2, 2, "999 Something Ln."],
                        [3, "Jones", 2, 2, "999 Something Ln."]))
        AssertEqual(people,
                    MakeRelation(
                        ["id", "name", "houseID"],
                        [1, "Stevens", 1],
                        [2, "Stanley", 2],
                        [3, "Jones", 2]))
        AssertEqual(houses,
                    MakeRelation(
                        ["id", "address"],
                        [1, "123 Main St."],
                        [2, "999 Something Ln."]))
    }
    
    func testProjectUpdate() {
        let db = makeDB().db
        let r = db.getOrCreateRelation("people", scheme: ["first", "last", "pet"]).ok!
        XCTAssertNil(r.add(["first": "Steve", "last": "Jobs", "pet": "cat"]).err)
        XCTAssertNil(r.add(["first": "Lisa", "last": "Jobs", "pet": "cat"]).err)
        XCTAssertNil(r.add(["first": "Cindy", "last": "Jobs", "pet": "dog"]).err)
        XCTAssertNil(r.add(["first": "Allen", "last": "Jones", "pet": "dog"]).err)
        
        var projected = r.project(["last", "pet"])
        _ = projected.update(Attribute("pet") *== "cat", newValues: ["last": "Smith"])
        
        AssertEqual(r,
                    MakeRelation(
                        ["first", "last", "pet"],
                        ["Steve", "Smith", "cat"],
                        ["Lisa", "Smith", "cat"],
                        ["Cindy", "Jobs", "dog"],
                        ["Allen", "Jones", "dog"]))
    }
    
    func testDifferenceUpdate() {
        let db = makeDB().db
        let r1 = db.getOrCreateRelation("people1", scheme: ["first", "last", "pet"]).ok!
        XCTAssertNil(r1.add(["first": "Steve", "last": "Jobs", "pet": "cat"]).err)
        XCTAssertNil(r1.add(["first": "Lisa", "last": "Jobs", "pet": "cat"]).err)
        XCTAssertNil(r1.add(["first": "Cindy", "last": "Jobs", "pet": "dog"]).err)
        XCTAssertNil(r1.add(["first": "Allen", "last": "Jones", "pet": "dog"]).err)
        
        let r2 = db.getOrCreateRelation("people2", scheme: ["first", "last", "pet"]).ok!
        XCTAssertNil(r2.add(["first": "Steve", "last": "Jobs", "pet": "cat"]).err)
        XCTAssertNil(r2.add(["first": "Cindy", "last": "Jobs", "pet": "dog"]).err)
        
        var difference = r1.difference(r2)
        _ = difference.update(Attribute("pet") *== "cat", newValues: ["last": "Smith"])
        
        AssertEqual(r1,
                    MakeRelation(
                        ["first", "last", "pet"],
                        ["Steve", "Jobs", "cat"],
                        ["Lisa", "Smith", "cat"],
                        ["Cindy", "Jobs", "dog"],
                        ["Allen", "Jones", "dog"]))
        
        AssertEqual(r2,
                    MakeRelation(
                        ["first", "last", "pet"],
                        ["Steve", "Jobs", "cat"],
                        ["Cindy", "Jobs", "dog"]))
    }
    
    func testIntersectionUpdate() {
        let db = makeDB().db
        let r1 = db.getOrCreateRelation("people1", scheme: ["first", "last", "pet"]).ok!
        XCTAssertNil(r1.add(["first": "Steve", "last": "Jobs", "pet": "cat"]).err)
        XCTAssertNil(r1.add(["first": "Lisa", "last": "Jobs", "pet": "cat"]).err)
        XCTAssertNil(r1.add(["first": "Cindy", "last": "Jobs", "pet": "dog"]).err)
        XCTAssertNil(r1.add(["first": "Allen", "last": "Jones", "pet": "dog"]).err)
        
        let r2 = db.getOrCreateRelation("people2", scheme: ["first", "last", "pet"]).ok!
        XCTAssertNil(r2.add(["first": "Steve", "last": "Jobs", "pet": "cat"]).err)
        XCTAssertNil(r2.add(["first": "Cindy", "last": "Jobs", "pet": "dog"]).err)
        
        var intersection = r1.intersection(r2)
        _ = intersection.update(Attribute("pet") *== "cat", newValues: ["last": "Smith"])
        
        AssertEqual(r1,
                    MakeRelation(
                        ["first", "last", "pet"],
                        ["Steve", "Smith", "cat"],
                        ["Lisa", "Jobs", "cat"],
                        ["Cindy", "Jobs", "dog"],
                        ["Allen", "Jones", "dog"]))
        
        AssertEqual(r2,
                    MakeRelation(
                        ["first", "last", "pet"],
                        ["Steve", "Smith", "cat"],
                        ["Cindy", "Jobs", "dog"]))
    }
    
    func testUnionUpdate() {
        let db = makeDB().db
        let r1 = db.getOrCreateRelation("people1", scheme: ["first", "last", "pet"]).ok!
        XCTAssertNil(r1.add(["first": "Lisa", "last": "Jobs", "pet": "cat"]).err)
        XCTAssertNil(r1.add(["first": "Allen", "last": "Jones", "pet": "dog"]).err)
        
        let r2 = db.getOrCreateRelation("people2", scheme: ["first", "last", "pet"]).ok!
        XCTAssertNil(r2.add(["first": "Steve", "last": "Jobs", "pet": "cat"]).err)
        XCTAssertNil(r2.add(["first": "Cindy", "last": "Jobs", "pet": "dog"]).err)
        
        var union = r1.union(r2)
        _ = union.update(Attribute("pet") *== "cat", newValues: ["last": "Smith"])
        
        AssertEqual(r1,
                    MakeRelation(
                        ["first", "last", "pet"],
                        ["Lisa", "Smith", "cat"],
                        ["Allen", "Jones", "dog"]))
        
        AssertEqual(r2,
                    MakeRelation(
                        ["first", "last", "pet"],
                        ["Steve", "Smith", "cat"],
                        ["Cindy", "Jobs", "dog"]))
    }
    
    func testNotSelect() {
        let FLIGHTS = makeSQLRelation("FLIGHTS",
                                      ["NUMBER", "FROM",   "TO",          "DEPARTS", "ARRIVES"],
                                      ["83",     "JFK",    "O'Hare",      "11:30a",  "1:43p"],
                                      ["84",     "O'Hare", "JFK",         "3:00p",   "5:55p"],
                                      ["109",    "JFK",    "Los Angeles", "9:50p",   "2:52a"],
                                      ["213",    "JFK",    "Boston",      "11:43a",  "12:45p"],
                                      ["214",    "Boston", "O'Hare",      "2:20p",   "3:12p"]
        )
        
        AssertEqual(FLIGHTS.select(*!(Attribute("NUMBER") *== "83")),
                    MakeRelation(
                        ["NUMBER", "FROM",   "TO",          "DEPARTS", "ARRIVES"],
                        ["84",     "O'Hare", "JFK",         "3:00p",   "5:55p"],
                        ["109",    "JFK",    "Los Angeles", "9:50p",   "2:52a"],
                        ["213",    "JFK",    "Boston",      "11:43a",  "12:45p"],
                        ["214",    "Boston", "O'Hare",      "2:20p",   "3:12p"]))
        
        AssertEqual(FLIGHTS.select(*!(Attribute("NUMBER") *== "83") *&& *!(Attribute("NUMBER") *== "84")),
                    MakeRelation(
                        ["NUMBER", "FROM",   "TO",          "DEPARTS", "ARRIVES"],
                        ["109",    "JFK",    "Los Angeles", "9:50p",   "2:52a"],
                        ["213",    "JFK",    "Boston",      "11:43a",  "12:45p"],
                        ["214",    "Boston", "O'Hare",      "2:20p",   "3:12p"]))
        
    }
    
    func testNotUpdate() {
        let FLIGHTS = makeSQLRelation("FLIGHTS",
                                      ["NUMBER", "FROM",   "TO",          "DEPARTS", "ARRIVES"],
                                      ["83",     "JFK",    "O'Hare",      "11:30a",  "1:43p"],
                                      ["84",     "O'Hare", "JFK",         "3:00p",   "5:55p"],
                                      ["109",    "JFK",    "Los Angeles", "9:50p",   "2:52a"],
                                      ["213",    "JFK",    "Boston",      "11:43a",  "12:45p"],
                                      ["214",    "Boston", "O'Hare",      "2:20p",   "3:12p"]
        )
        
        _ = FLIGHTS.update(*!(Attribute("NUMBER") *== "83") *&& *!(Attribute("NUMBER") *== "84"), newValues: ["FROM": "Miami"])
        
        AssertEqual(FLIGHTS,
                    MakeRelation(
                        ["NUMBER", "FROM",   "TO",          "DEPARTS", "ARRIVES"],
                        ["83",     "JFK",    "O'Hare",      "11:30a",  "1:43p"],
                        ["84",     "O'Hare", "JFK",         "3:00p",   "5:55p"],
                        ["109",    "Miami",  "Los Angeles", "9:50p",   "2:52a"],
                        ["213",    "Miami",  "Boston",      "11:43a",  "12:45p"],
                        ["214",    "Miami",  "O'Hare",      "2:20p",   "3:12p"]))
    }
    
    func testTransactionConflict() {
        let (path, db1) = makeDB()
        _ = db1.createRelation("r", scheme: ["n"])
        let r1 = db1["r"]!
        
        _ = r1.add(["n": 1])
        
        let db2 = try! SQLiteDatabase(path)
        let r2 = db2["r"]!
        AssertEqual(r2, MakeRelation(["n"], [1]))
        
        let result = db1.transaction({
            let result = db2.transaction({
                let result = r2.update(Attribute("n") *== 1, newValues: ["n": 3])
                XCTAssertNil(result.err)
                
                let result2 = r1.delete(Attribute("n") *== 1)
                let err2 = result2.err as? SQLiteDatabase.Error
                XCTAssertNotNil(err2)
                XCTAssertEqual(err2?.code, SQLITE_BUSY)
                
                let result3 = r1.add(["n": 2])
                let err3 = result3.err as? SQLiteDatabase.Error
                XCTAssertNotNil(err3)
                XCTAssertEqual(err3?.code, SQLITE_BUSY)
                
                let result4 = r1.update(Attribute("n") *== 1, newValues: ["n": 4])
                let err4 = result4.err as? SQLiteDatabase.Error
                XCTAssertNotNil(err4)
                XCTAssertEqual(err4?.code, SQLITE_BUSY)
                
                return .commit
            })
            let err = result.err as? SQLiteDatabase.Error
            XCTAssertNotNil(err)
            XCTAssertEqual(err?.code, SQLITE_BUSY)
            
            return .commit
        })
        XCTAssertNil(result.err)
        
        AssertEqual(r2, MakeRelation(["n"], [3]))
    }
    
    func testTransactionRetry() {
        let (path, db1) = makeDB()
        _ = db1.createRelation("r", scheme: ["n"])
        let r1 = db1["r"]!
        
        _ = r1.add(["n": 1])
        
        let db2 = try! SQLiteDatabase(path)
        let r2 = db2["r"]!
        AssertEqual(r2, MakeRelation(["n"], [1]))
        
        var runNumber = 1
        let result = db1.transaction({
            if runNumber == 1 {
                _ = db2.transaction({
                    let result = r2.update(Attribute("n") *== 1, newValues: ["n": 3])
                    XCTAssertNil(result.err)
                    
                    if runNumber == 1 {
                        let result2 = r1.delete(Attribute("n") *== 1)
                        if db1.resultNeedsRetry(result2) {
                            runNumber += 1
                            return .retry
                        }
                    }
                    
                    return .commit
                })
            }
            return .commit
        })
        XCTAssertNil(result.err)
        XCTAssertEqual(runNumber, 2)
        AssertEqual(r2, MakeRelation(["n"], [3]))
    }
}
