
import XCTest
import libRelational

class RelationTests: DBTestCase {
    func testUnion() {
        let r = MakeRelation(["A",  "B",  "C"],
                             ["A1", "B1", "C1"],
                             ["A1", "B2", "C1"],
                             ["A2", "B1", "C2"]
        )
        let s = MakeRelation(["A",  "B",  "C"],
                             ["A1", "B2", "C1"],
                             ["A2", "B2", "C1"],
                             ["A2", "B2", "C2"]
        )
        
        AssertEqual(r.union(s),
                    MakeRelation(
                        ["A",  "B",  "C"],
                        ["A1", "B1", "C1"],
                        ["A1", "B2", "C1"],
                        ["A2", "B2", "C1"],
                        ["A2", "B1", "C2"],
                        ["A2", "B2", "C2"]))
    }
    
    func testIntersection() {
        let r = MakeRelation(["A",  "B",  "C"],
                             ["A1", "B1", "C1"],
                             ["A1", "B2", "C1"],
                             ["A2", "B1", "C2"]
        )
        let s = MakeRelation(["A",  "B",  "C"],
                             ["A1", "B2", "C1"],
                             ["A2", "B2", "C1"],
                             ["A2", "B2", "C2"]
        )
        
        AssertEqual(r.intersection(s),
                    MakeRelation(
                        ["A",  "B",  "C"],
                        ["A1", "B2", "C1"]))
    }
    
    func testDifference() {
        let r = MakeRelation(["A",  "B",  "C"],
                             ["A1", "B1", "C1"],
                             ["A1", "B2", "C1"],
                             ["A2", "B1", "C2"]
        )
        let s = MakeRelation(["A",  "B",  "C"],
                             ["A1", "B2", "C1"],
                             ["A2", "B2", "C1"],
                             ["A2", "B2", "C2"]
        )
        
        AssertEqual(r.difference(s),
                    MakeRelation(
                        ["A",  "B",  "C"],
                        ["A1", "B1", "C1"],
                        ["A2", "B1", "C2"]))
    }
    
    func testJoin() {
        let a = MakeRelation(
            ["A", "B"],
            ["X", "1"],
            ["Y", "2"]
        )
        let b = MakeRelation(
            ["B", "C"],
            ["1", "T"],
            ["3", "V"]
        )
        
        AssertEqual(a.join(b),
                    MakeRelation(
                        ["A", "B", "C"],
                        ["X", "1", "T"]))
    }
    
    func testProject() {
        let a = MakeRelation(
            ["A", "B"],
            ["X", "1"],
            ["Y", "1"]
        )
        
        AssertEqual(a.project(["B"]),
                    MakeRelation(
                        ["B"],
                        ["1"]))
    }
    
    func testSimpleMutation() {
        var FLIGHTS = MakeRelation(
            ["NUMBER", "FROM",   "TO",          "DEPARTS", "ARRIVES"],
            ["83",     "JFK",    "O'Hare",      "11:30a",  "1:43p"],
            ["84",     "O'Hare", "JFK",         "3:00p",   "5:55p"],
            ["109",    "JFK",    "Los Angeles", "9:50p",   "2:52a"],
            ["213",    "JFK",    "Boston",      "11:43a",  "12:45p"],
            ["214",    "Boston", "O'Hare",      "2:20p",   "3:12p"]
        )
        
        FLIGHTS.add(["NUMBER": "117", "FROM": "Atlanta", "TO": "Boston", "DEPARTS": "10:05p", "ARRIVES": "12:43a"])
        AssertEqual(FLIGHTS,
                    MakeRelation(
                        ["NUMBER", "FROM",   "TO",          "DEPARTS", "ARRIVES"],
                        ["83",     "JFK",    "O'Hare",      "11:30a",  "1:43p"],
                        ["84",     "O'Hare", "JFK",         "3:00p",   "5:55p"],
                        ["109",    "JFK",    "Los Angeles", "9:50p",   "2:52a"],
                        ["213",    "JFK",    "Boston",      "11:43a",  "12:45p"],
                        ["214",    "Boston", "O'Hare",      "2:20p",   "3:12p"],
                        ["117",    "Atlanta", "Boston",     "10:05p",  "12:43a"]))
        
        FLIGHTS.delete(["NUMBER": "83"])
        AssertEqual(FLIGHTS,
                    MakeRelation(
                        ["NUMBER", "FROM",   "TO",          "DEPARTS", "ARRIVES"],
                        ["84",     "O'Hare", "JFK",         "3:00p",   "5:55p"],
                        ["109",    "JFK",    "Los Angeles", "9:50p",   "2:52a"],
                        ["213",    "JFK",    "Boston",      "11:43a",  "12:45p"],
                        ["214",    "Boston", "O'Hare",      "2:20p",   "3:12p"],
                        ["117",    "Atlanta", "Boston",     "10:05p",  "12:43a"]))
        
        AssertEqual(FLIGHTS.select(["FROM": "Boston"]),
                    MakeRelation(
                        ["NUMBER", "FROM",   "TO",          "DEPARTS", "ARRIVES"],
                        ["214",    "Boston", "O'Hare",      "2:20p",   "3:12p"]))
        
        FLIGHTS.update(["NUMBER": "109"], newValues: ["DEPARTS": "9:40p", "ARRIVES": "2:42a"])
        AssertEqual(FLIGHTS,
                    MakeRelation(
                        ["NUMBER", "FROM",   "TO",          "DEPARTS", "ARRIVES"],
                        ["84",     "O'Hare", "JFK",         "3:00p",   "5:55p"],
                        ["109",    "JFK",    "Los Angeles", "9:40p",   "2:42a"],
                        ["213",    "JFK",    "Boston",      "11:43a",  "12:45p"],
                        ["214",    "Boston", "O'Hare",      "2:20p",   "3:12p"],
                        ["117",    "Atlanta", "Boston",     "10:05p",  "12:43a"]))
    }
    
    func testMoreProject() {
        let FLIGHTS = MakeRelation(
            ["NUMBER", "FROM",   "TO",          "DEPARTS", "ARRIVES"],
            ["83",     "JFK",    "O'Hare",      "11:30a",  "1:43p"],
            ["84",     "O'Hare", "JFK",         "3:00p",   "5:55p"],
            ["109",    "JFK",    "Los Angeles", "9:50p",   "2:52a"],
            ["213",    "JFK",    "Boston",      "11:43a",  "12:45p"],
            ["214",    "Boston", "O'Hare",      "2:20p",   "3:12p"]
        )
        
        AssertEqual(FLIGHTS.project(["DEPARTS", "ARRIVES"]),
                    MakeRelation(
                        ["DEPARTS", "ARRIVES"],
                        ["11:30a",  "1:43p"],
                        ["3:00p",   "5:55p"],
                        ["9:50p",   "2:52a"],
                        ["11:43a",  "12:45p"],
                        ["2:20p",   "3:12p"]))
        
        AssertEqual(FLIGHTS.project(["DEPARTS"]),
                    MakeRelation(
                        ["DEPARTS"],
                        ["11:30a"],
                        ["3:00p"],
                        ["9:50p"],
                        ["11:43a"],
                        ["2:20p"]))
        
        AssertEqual(FLIGHTS.project(["FROM"]),
                    MakeRelation(
                        ["FROM"],
                        ["JFK"],
                        ["O'Hare"],
                        ["JFK"],
                        ["Boston"]))
    }
    
    func testMoreJoin() {
        let usable = MakeRelation(
            ["FLIGHT", "EQUIPMENT"],
            ["83", "727"],
            ["83", "747"],
            ["84", "727"],
            ["84", "747"],
            ["109", "707"]
        )
        
        let certified = MakeRelation(
            ["PILOT", "EQUIPMENT"],
            ["Simmons", "707"],
            ["Simmons", "727"],
            ["Barth", "747"],
            ["Hill", "727"],
            ["Hill", "747"]
        )
        
        let options = usable.join(certified)
        AssertEqual(options,
                    MakeRelation(
                        ["FLIGHT", "EQUIPMENT", "PILOT"],
                        ["83", "727", "Simmons"],
                        ["83", "727", "Hill"],
                        ["83", "747", "Hill"],
                        ["83", "747", "Barth"],
                        ["84", "727", "Simmons"],
                        ["84", "727", "Hill"],
                        ["84", "747", "Hill"],
                        ["84", "747", "Barth"],
                        ["109", "707", "Simmons"]))
        
        AssertEqual(options.project(["FLIGHT", "PILOT"]),
                    MakeRelation(
                        ["FLIGHT", "PILOT"],
                        ["83", "Simmons"],
                        ["83", "Hill"],
                        ["83", "Barth"],
                        ["84", "Simmons"],
                        ["84", "Hill"],
                        ["84", "Barth"],
                        ["109", "Simmons"]))
        
        AssertEqual(options.select(["FLIGHT": "84"]),
                    MakeRelation(
                        ["FLIGHT", "EQUIPMENT", "PILOT"],
                        ["84", "727", "Simmons"],
                        ["84", "727", "Hill"],
                        ["84", "747", "Hill"],
                        ["84", "747", "Barth"]))

        let flight84 = MakeRelation(["FLIGHT"], ["84"])
        AssertEqual(options.join(flight84),
                    MakeRelation(
                        ["FLIGHT", "EQUIPMENT", "PILOT"],
                        ["84", "727", "Simmons"],
                        ["84", "727", "Hill"],
                        ["84", "747", "Hill"],
                        ["84", "747", "Barth"]))
    }
    
    func testDivide() {
        let q = MakeRelation(
            ["EQUIPMENT"],
            ["707"],
            ["727"],
            ["747"]
        )
        
        let s = MakeRelation(
            ["EQUIPMENT"],
            ["707"]
        )
        
        let certified = MakeRelation(
            ["PILOT", "EQUIPMENT"],
            ["Desmond", "707"],
            ["Desmond", "727"],
            ["Desmond", "747"],
            ["Doyle", "707"],
            ["Doyle", "727"],
            ["Davis", "707"],
            ["Davis", "727"],
            ["Davis", "747"],
            ["Davis", "1011"],
            ["Dow", "727"]
            ).setDefaultSort("PILOT")
        
        AssertEqual(certified.divide(q),
                    MakeRelation(
                        ["PILOT"],
                        ["Desmond"],
                        ["Davis"]))
        
        AssertEqual(certified.divide(s),
                    MakeRelation(
                        ["PILOT"],
                        ["Desmond"],
                        ["Doyle"],
                        ["Davis"]))
    }
    
    func testBuildFromJoinAndUnion() {
        let pilots = (["PILOT": "Desmond"] as ConcreteRelation).join(["EQUIPMENT": "707"] as ConcreteRelation).union((["PILOT": "Davis"] as ConcreteRelation).join(["EQUIPMENT": "707"] as ConcreteRelation))
        AssertEqual(pilots,
                    MakeRelation(
                        ["PILOT", "EQUIPMENT"],
                        ["Desmond", "707"],
                        ["Davis", "707"]))
    }
    
    func testRename() {
        let usedfor = MakeRelation(
            ["FLIGHT", "DATE",  "PLANENUM"],
            ["12",     "6 Jan", "707-82"],
            ["12",     "7 Jan", "707-82"],
            ["13",     "6 Jan", "707-82"],
            ["26",     "6 Jan", "747-16"],
            ["26",     "7 Jan", "747-18"],
            ["27",     "6 Jan", "747-16"],
            ["27",     "7 Jan", "747-2"],
            ["60",     "6 Jan", "707-82"],
            ["60",     "7 Jan", "727-6"]
        )
        
        let usedforRenamed = usedfor.renameAttributes(["FLIGHT": "FLIGHT2"])
        AssertEqual(usedforRenamed,
                    MakeRelation(
                        ["FLIGHT2", "DATE",  "PLANENUM"],
                        ["12",      "6 Jan", "707-82"],
                        ["12",      "7 Jan", "707-82"],
                        ["13",      "6 Jan", "707-82"],
                        ["26",      "6 Jan", "747-16"],
                        ["26",      "7 Jan", "747-18"],
                        ["27",      "6 Jan", "747-16"],
                        ["27",      "7 Jan", "747-2"],
                        ["60",      "6 Jan", "707-82"],
                        ["60",      "7 Jan", "727-6"]))
        
        AssertEqual(usedfor.join(usedforRenamed).project(["FLIGHT", "FLIGHT2"]),
                    MakeRelation(
                        ["FLIGHT", "FLIGHT2"],
                        ["12",     "12"],
                        ["27",     "27"],
                        ["27",     "26"],
                        ["26",     "27"],
                        ["26",     "26"],
                        ["12",     "13"],
                        ["12",     "60"],
                        ["13",     "12"],
                        ["13",     "13"],
                        ["13",     "60"],
                        ["60",     "12"],
                        ["60",     "13"],
                        ["60",     "60"]))
        
        AssertEqual(usedforRenamed.renameAttributes(["DATE": "PLANENUM", "PLANENUM": "DATE"]),
                    MakeRelation(
                        ["FLIGHT2", "PLANENUM", "DATE"],
                        ["12",      "6 Jan", "707-82"],
                        ["12",      "7 Jan", "707-82"],
                        ["13",      "6 Jan", "707-82"],
                        ["26",      "6 Jan", "747-16"],
                        ["26",      "7 Jan", "747-18"],
                        ["27",      "6 Jan", "747-16"],
                        ["27",      "7 Jan", "747-2"],
                        ["60",      "6 Jan", "707-82"],
                        ["60",      "7 Jan", "727-6"]))
    }
    
    func testEquijoin() {
        let routes = MakeRelation(
            ["NUMBER", "FROM",    "TO"],
            ["84",     "O'Hare",  "JFK"],
            ["109",    "JFK",     "Los Angeles"],
            ["117",    "Atlanta", "Boston"],
            ["213",    "JFK",     "Boston"],
            ["214",    "Boston",  "JFK"]
        )
        
        let based = MakeRelation(
            ["PILOT", "AIRPORT"],
            ["Terhune", "JFK"],
            ["Temple", "Atlanta"],
            ["Taylor", "Atlanta"],
            ["Tarbell", "Boston"],
            ["Todd", "Los Angeles"],
            ["Truman", "O'Hare"]
        )
        
        AssertEqual(routes.equijoin(based, matching: ["FROM": "AIRPORT"]),
                    MakeRelation(
                        ["AIRPORT",  "FROM",     "NUMBER", "PILOT",   "TO"],
                        ["O'Hare",   "O'Hare",   "84",     "Truman",  "JFK"],
                        ["Atlanta",  "Atlanta",  "117",    "Taylor",  "Boston"],
                        ["Atlanta",  "Atlanta",  "117",    "Temple",  "Boston"],
                        ["Boston",   "Boston",   "214",    "Tarbell", "JFK"],
                        ["JFK",      "JFK",      "109",    "Terhune", "Los Angeles"],
                        ["JFK",      "JFK",      "213",    "Terhune", "Boston"]))

    }
    
    func testSelectWithComparisons() {
        let FLIGHTS = MakeRelation(
            ["NUMBER", "FROM",   "TO",          "DEPARTS", "ARRIVES"],
            ["83",     "JFK",    "O'Hare",      1130,       1343],
            ["84",     "O'Hare", "JFK",         1500,       1755],
            ["109",    "JFK",    "Los Angeles", 2150,       252],
            ["213",    "JFK",    "Boston",      1143,       1245],
            ["214",    "Boston", "O'Hare",      1420,       1512]
        )
        
        let times = FLIGHTS.project(["NUMBER", "DEPARTS", "ARRIVES"])
        AssertEqual(times.select([ComparisonTerm(Attribute("ARRIVES"), LTComparator(), RelationValue.Integer(1300))]),
                    MakeRelation(
                        ["NUMBER", "DEPARTS", "ARRIVES"],
                        ["109", 2150, 0252],
                        ["213", 1143, 1245]))
        
        let twoHoursLT = AnyComparator({ (lhs, rhs) in
            let lhsN = lhs.get() as Int64? ?? -1
            let rhsN = rhs.get() as Int64? ?? -1
            return ((rhsN + 2400) - lhsN) % 2400 >= 200
        })
        
        AssertEqual(times.select([ComparisonTerm(Attribute("DEPARTS"), twoHoursLT, Attribute("ARRIVES"))]),
                    MakeRelation(
                        ["NUMBER", "DEPARTS", "ARRIVES"],
                        ["109", 2150, 252],
                        ["84", 1500, 1755],
                        ["83", 1130, 1343]))
    }
    
    func testThetajoin() {
        let timesab = MakeRelation(
            ["NUMBER", "DEPARTS", "ARRIVES"],
            ["60",  "0940", "1145"],
            ["91",  "1250", "1447"],
            ["112", "1605", "1815"],
            ["306", "2030", "2225"],
            ["40",  "2115", "2311"]
        )
        let timesbc = MakeRelation(
            ["NUMBER", "DEPARTS", "ARRIVES"],
            ["11",  "0830", "0952"],
            ["60",  "1225", "1343"],
            ["156", "1620", "1740"],
            ["158", "1910", "2035"]
        )
        
        let connectac = timesab.thetajoin(timesbc.renamePrime(), terms: [ComparisonTerm(Attribute("ARRIVES"), LTComparator(), Attribute("DEPARTS'"))])
        AssertEqual(connectac,
                    MakeRelation(
                        ["ARRIVES", "ARRIVES'", "DEPARTS", "DEPARTS'", "NUMBER", "NUMBER'"],
                        ["1815",    "2035",     "1605",    "1910",     "112",    "158"],
                        ["1447",    "1740",     "1250",    "1620",     "91",     "156"],
                        ["1447",    "2035",     "1250",    "1910",     "91",     "158"],
                        ["1145",    "1343",     "0940",    "1225",     "60",     "60"],
                        ["1145",    "1740",     "0940",    "1620",     "60",     "156"],
                        ["1145",    "2035",     "0940",    "1910",     "60",     "158"]))
    }
    
    func testSplit() {
        let FLIGHTS = MakeRelation(
            ["NUMBER", "FROM",   "TO",          "DEPARTS", "ARRIVES"],
            ["83",     "JFK",    "O'Hare",      "1130",    "1343"],
            ["84",     "O'Hare", "JFK",         "1500",    "1755"],
            ["109",    "JFK",    "Los Angeles", "2150",    "0252"],
            ["213",    "JFK",    "Boston",      "1143",    "1245"],
            ["214",    "Boston", "O'Hare",      "1420",    "1512"]
        )
        
        let split = FLIGHTS.split([ComparisonTerm(Attribute("FROM"), EqualityComparator(), "JFK")])
        AssertEqual(split.0,
                    MakeRelation(
                        ["NUMBER", "FROM",   "TO",          "DEPARTS", "ARRIVES"],
                        ["83",     "JFK",    "O'Hare",      "1130",    "1343"],
                        ["109",    "JFK",    "Los Angeles", "2150",    "0252"],
                        ["213",    "JFK",    "Boston",      "1143",    "1245"]))
        AssertEqual(split.1,
                    MakeRelation(
                        ["NUMBER", "FROM",   "TO",          "DEPARTS", "ARRIVES"],
                        ["84",     "O'Hare", "JFK",         "1500",    "1755"],
                        ["214",    "Boston", "O'Hare",      "1420",    "1512"]))
    }
    
    func testForeach() {
        let r1 = MakeRelation(
            ["first", "last", "pet"],
            ["Steve", "Smith", "cat"],
            ["Lisa", "Jobs", "cat"],
            ["Cindy", "Jobs", "dog"],
            ["Allen", "Jones", "dog"])
        var r2 = MakeRelation(
            ["first", "last", "pet"])
        
        XCTAssertNil(r1.forEach({ row, stop in r2.add(row) }).err)
        AssertEqual(r1, r2)
        
        var callCount = 0
        XCTAssertNil(r1.forEach({ row, stop in callCount += 1; stop() }).err)
        XCTAssertEqual(callCount, 1)
    }
}