
import XCTest
import libRelational

class SQLiteDatabaseTests: DBTestCase {
    func testSQLiteBasics() {
        let db = makeDB().db.sqliteDatabase
        db.createRelation("FLIGHTS", scheme: ["NUMBER", "FROM", "TO"])
        db.createRelation("FLIGHTS", scheme: ["NUMBER", "FROM", "TO"])
        
        let FLIGHTS = db["FLIGHTS"]!
        FLIGHTS.add(["NUMBER": "123", "FROM": "JFK", "TO": "Unknown"])
        FLIGHTS.add(["NUMBER": "124", "FROM": "JFK", "TO": "A"])
        FLIGHTS.add(["NUMBER": "125", "FROM": "JFK", "TO": "B"])
        FLIGHTS.add(["NUMBER": "126", "FROM": "JFK", "TO": "C"])
        FLIGHTS.add(["NUMBER": "127", "FROM": "JFK", "TO": "D"])
        FLIGHTS.add(["NUMBER": "128", "FROM": "JFK", "TO": "A"])
        FLIGHTS.add(["NUMBER": "129", "FROM": "JFK", "TO": "A"])
        FLIGHTS.add(["NUMBER": "888", "FROM": "Here", "TO": "There"])
        FLIGHTS.add(["NUMBER": "3", "FROM": "Atlanta", "TO": "Atlanta"])
        
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
        
        FLIGHTS.update(Attribute("NUMBER") *== "888", newValues: ["FROM": "Tennessee", "TO": "Spotsylvania"])
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
        
        FLIGHTS.delete(Attribute("FROM") *== "JFK")
        AssertEqual(FLIGHTS,
                    MakeRelation(
                        ["FROM",     "NUMBER", "TO"],
                        ["Tennessee","888",    "Spotsylvania"],
                        ["Atlanta",  "3",      "Atlanta"]))
    }
    
    func testCommittedTransaction() {
        let db = makeDB().db.sqliteDatabase
        db.createRelation("FLIGHTS", scheme: ["NUMBER", "FROM", "TO"])
        
        db.transaction({
            let FLIGHTS = db["FLIGHTS"]!
            FLIGHTS.add(["NUMBER": "123", "FROM": "JFK", "TO": "Unknown"])
            FLIGHTS.add(["NUMBER": "124", "FROM": "JFK", "TO": "A"])
            FLIGHTS.add(["NUMBER": "125", "FROM": "JFK", "TO": "B"])
            FLIGHTS.add(["NUMBER": "126", "FROM": "JFK", "TO": "C"])
            FLIGHTS.add(["NUMBER": "127", "FROM": "JFK", "TO": "D"])
            FLIGHTS.add(["NUMBER": "128", "FROM": "JFK", "TO": "A"])
            FLIGHTS.add(["NUMBER": "129", "FROM": "JFK", "TO": "A"])
            FLIGHTS.add(["NUMBER": "888", "FROM": "Here", "TO": "There"])
            FLIGHTS.add(["NUMBER": "3", "FROM": "Atlanta", "TO": "Atlanta"])
            return .Commit
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
        let db = makeDB().db.sqliteDatabase
        db.createRelation("FLIGHTS", scheme: ["NUMBER", "FROM", "TO"])
        
        db.transaction({
            let FLIGHTS = db["FLIGHTS"]!
            FLIGHTS.add(["NUMBER": "123", "FROM": "JFK", "TO": "Unknown"])
            FLIGHTS.add(["NUMBER": "124", "FROM": "JFK", "TO": "A"])
            FLIGHTS.add(["NUMBER": "125", "FROM": "JFK", "TO": "B"])
            FLIGHTS.add(["NUMBER": "126", "FROM": "JFK", "TO": "C"])
            FLIGHTS.add(["NUMBER": "127", "FROM": "JFK", "TO": "D"])
            FLIGHTS.add(["NUMBER": "128", "FROM": "JFK", "TO": "A"])
            FLIGHTS.add(["NUMBER": "129", "FROM": "JFK", "TO": "A"])
            FLIGHTS.add(["NUMBER": "888", "FROM": "Here", "TO": "There"])
            FLIGHTS.add(["NUMBER": "3", "FROM": "Atlanta", "TO": "Atlanta"])
            return .Rollback
        })
        
        AssertEqual(db["FLIGHTS"]!,
                    MakeRelation(
                        ["FROM", "NUMBER", "TO"]))
    }
    
    func testBasicObservation() {
        let db = makeDB().db.sqliteDatabase
        
        XCTAssertNil(db.createRelation("test", scheme: ["column"]).err)
        let r = db["test"]!
        
        var changeCount = 0
        let removal = r.addChangeObserver({ _ in changeCount += 1 })
        
        r.add(["column": "42"])
        XCTAssertEqual(changeCount, 1)
        
        r.update(Attribute("column") *== "42", newValues: ["column": "43"])
        XCTAssertEqual(changeCount, 2)
        
        r.delete(Attribute("column") *== "43")
        XCTAssertEqual(changeCount, 3)
        
        removal()
        r.add(["column": "123"])
        XCTAssertEqual(changeCount, 3)
    }
    
    func testJoinObservation() {
        let db = makeDB().db.sqliteDatabase
        
        XCTAssertNil(db.createRelation("a", scheme: ["1", "2"]).err)
        XCTAssertNil(db.createRelation("b", scheme: ["2", "3"]).err)
        
        let a = db["a"]!
        let b = db["b"]!
        
        a.add(["1": "X", "2": "X"])
        a.add(["1": "X", "2": "Y"])
        a.add(["1": "Y", "2": "Z"])
        
        b.add(["2": "X", "3": "X"])
        b.add(["2": "X", "3": "Y"])
        b.add(["2": "Y", "3": "Z"])
        
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
        a.delete(Attribute("2") *== "Y")
        XCTAssertTrue(changed)
        AssertEqual(joined,
                    MakeRelation(
                        ["1", "2", "3"],
                        ["X", "X", "X"],
                        ["X", "X", "Y"]))
        
        changed = false
        b.add(["2": "Z", "3": "Z"])
        XCTAssertTrue(changed)
        AssertEqual(joined,
                    MakeRelation(
                        ["1", "2", "3"],
                        ["X", "X", "X"],
                        ["X", "X", "Y"],
                        ["Y", "Z", "Z"]))
        
        removal()
        changed = false
        a.delete(Attribute("1") *== "X")
        XCTAssertFalse(changed)
    }
    
    func testBinding() {
        let db = makeDB().db.sqliteDatabase
        
        let scheme: Scheme = ["id", "name"]
        XCTAssertNil(db.createRelation("people", scheme: scheme).err)
        
        let r = db["people"]!
        XCTAssertNil(r.add(["id": 1, "name": "Joe"]).err)
        XCTAssertNil(r.add(["id": 2, "name": "Steve"]).err)
        XCTAssertNil(r.add(["id": 3, "name": "Jane"]).err)
        
        var currentName: String?
        let binding = SQLiteBinding(database: db, tableName: "people", key: ["id": 2], attribute: "name", changeObserver: { currentName = $0.get() })
        XCTAssertEqual(currentName, "Steve")
        
        binding.set("Roberta")
        XCTAssertEqual(currentName, "Roberta")
        
        r.update(Attribute("id") *== RelationValue.Integer(2), newValues: ["name": "Tina"])
        XCTAssertEqual(currentName, "Tina")
    }
    
    func testUpdates() {
        let db = makeDB().db.sqliteDatabase
        
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
        let db = makeDB().db.sqliteDatabase
        let r = db.getOrCreateRelation("people", scheme: ["first", "last", "pet"]).ok!
        XCTAssertNil(r.add(["first": "Steve", "last": "Jobs", "pet": "cat"]).err)
        XCTAssertNil(r.add(["first": "Lisa", "last": "Jobs", "pet": "cat"]).err)
        XCTAssertNil(r.add(["first": "Cindy", "last": "Jobs", "pet": "dog"]).err)
        XCTAssertNil(r.add(["first": "Allen", "last": "Jones", "pet": "dog"]).err)
        
        var projected = r.project(["last", "pet"])
        projected.update(Attribute("pet") *== "cat", newValues: ["last": "Smith"])
        
        AssertEqual(r,
                    MakeRelation(
                        ["first", "last", "pet"],
                        ["Steve", "Smith", "cat"],
                        ["Lisa", "Smith", "cat"],
                        ["Cindy", "Jobs", "dog"],
                        ["Allen", "Jones", "dog"]))
    }
    
    func testDifferenceUpdate() {
        let db = makeDB().db.sqliteDatabase
        let r1 = db.getOrCreateRelation("people1", scheme: ["first", "last", "pet"]).ok!
        XCTAssertNil(r1.add(["first": "Steve", "last": "Jobs", "pet": "cat"]).err)
        XCTAssertNil(r1.add(["first": "Lisa", "last": "Jobs", "pet": "cat"]).err)
        XCTAssertNil(r1.add(["first": "Cindy", "last": "Jobs", "pet": "dog"]).err)
        XCTAssertNil(r1.add(["first": "Allen", "last": "Jones", "pet": "dog"]).err)
        
        let r2 = db.getOrCreateRelation("people2", scheme: ["first", "last", "pet"]).ok!
        XCTAssertNil(r2.add(["first": "Steve", "last": "Jobs", "pet": "cat"]).err)
        XCTAssertNil(r2.add(["first": "Cindy", "last": "Jobs", "pet": "dog"]).err)
        
        var difference = r1.difference(r2)
        difference.update(Attribute("pet") *== "cat", newValues: ["last": "Smith"])
        
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
        let db = makeDB().db.sqliteDatabase
        let r1 = db.getOrCreateRelation("people1", scheme: ["first", "last", "pet"]).ok!
        XCTAssertNil(r1.add(["first": "Steve", "last": "Jobs", "pet": "cat"]).err)
        XCTAssertNil(r1.add(["first": "Lisa", "last": "Jobs", "pet": "cat"]).err)
        XCTAssertNil(r1.add(["first": "Cindy", "last": "Jobs", "pet": "dog"]).err)
        XCTAssertNil(r1.add(["first": "Allen", "last": "Jones", "pet": "dog"]).err)
        
        let r2 = db.getOrCreateRelation("people2", scheme: ["first", "last", "pet"]).ok!
        XCTAssertNil(r2.add(["first": "Steve", "last": "Jobs", "pet": "cat"]).err)
        XCTAssertNil(r2.add(["first": "Cindy", "last": "Jobs", "pet": "dog"]).err)
        
        var intersection = r1.intersection(r2)
        intersection.update(Attribute("pet") *== "cat", newValues: ["last": "Smith"])
        
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
        let db = makeDB().db.sqliteDatabase
        let r1 = db.getOrCreateRelation("people1", scheme: ["first", "last", "pet"]).ok!
        XCTAssertNil(r1.add(["first": "Lisa", "last": "Jobs", "pet": "cat"]).err)
        XCTAssertNil(r1.add(["first": "Allen", "last": "Jones", "pet": "dog"]).err)
        
        let r2 = db.getOrCreateRelation("people2", scheme: ["first", "last", "pet"]).ok!
        XCTAssertNil(r2.add(["first": "Steve", "last": "Jobs", "pet": "cat"]).err)
        XCTAssertNil(r2.add(["first": "Cindy", "last": "Jobs", "pet": "dog"]).err)
        
        var union = r1.union(r2)
        union.update(Attribute("pet") *== "cat", newValues: ["last": "Smith"])
        
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
}
