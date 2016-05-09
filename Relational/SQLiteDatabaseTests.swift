
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
        
        AssertEqual(FLIGHTS.select([ComparisonTerm(Attribute("NUMBER"), LTComparator(), "125")]),
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
        
        FLIGHTS.update([ComparisonTerm(Attribute("NUMBER"), EqualityComparator(), "888")], newValues: ["FROM": "Tennessee", "TO": "Spotsylvania"])
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
        
        FLIGHTS.delete([ComparisonTerm(Attribute("FROM"), EqualityComparator(), "JFK")])
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
}
