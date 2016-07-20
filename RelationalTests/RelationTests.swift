//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

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
        AssertEqual(times.select(SelectExpressionBinaryOperator(lhs: Attribute("ARRIVES"), op: LTComparator(), rhs: RelationValue.Integer(1300))),
                    MakeRelation(
                        ["NUMBER", "DEPARTS", "ARRIVES"],
                        ["109", 2150, 0252],
                        ["213", 1143, 1245]))
        
        let twoHoursLT = AnyComparator({ (lhs, rhs) in
            let lhsN = lhs.get() as Int64? ?? -1
            let rhsN = rhs.get() as Int64? ?? -1
            return ((rhsN + 2400) - lhsN) % 2400 >= 200
        })
        
        AssertEqual(times.select(SelectExpressionBinaryOperator(lhs: Attribute("DEPARTS"), op: twoHoursLT, rhs: Attribute("ARRIVES"))),
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
        
        let connectac = timesab.thetajoin(timesbc.renamePrime(), query: SelectExpressionBinaryOperator(lhs: Attribute("ARRIVES"), op: LTComparator(), rhs: Attribute("DEPARTS'")))
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
        
        let split = FLIGHTS.split(Attribute("FROM") *== "JFK")
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

    func testMinMax() {
        let empty = MakeRelation(
            ["id", "name", "count"])
        
        AssertEqual(empty.min("count"), nil)
        AssertEqual(empty.max("count"), nil)
        
        let r = MakeRelation(
            ["id", "name", "count"],
            [1,    "cat",  1],
            [2,    "dog",  3],
            [3,    "fish", 2],
            [4,    "ant",  3])
        
        AssertEqual(r.min("count"),
                    MakeRelation(
                        ["count"],
                        [1]))
        AssertEqual(r.max("count"),
                    MakeRelation(
                        ["count"],
                        [3]))
    }
    
    func testCount() {
        let empty = MakeRelation(
            ["id", "name"])
        
        AssertEqual(empty.count(),
                    MakeRelation(
                        ["count"],
                        [0]))
        
        let r = MakeRelation(
            ["id", "name"],
            [1,    "cat"],
            [2,    "dog"],
            [3,    "fish"],
            [4,    "ant"])
        
        AssertEqual(r.count(),
                    MakeRelation(
                        ["count"],
                        [4]))
    }
    
    func testOtherwise() {
        let empty = MakeRelation(
            ["id", "name"])
        let r1 = MakeRelation(
            ["id", "name"],
            [1,    "cat"],
            [2,    "dog"],
            [3,    "fish"],
            [4,    "ant"])
        let r2 = MakeRelation(
            ["id", "name"],
            [5,    "duck"],
            [6,    "loon"])
        
        AssertEqual(r1.otherwise(r2), r1)
        AssertEqual(r2.otherwise(r1), r2)
        AssertEqual(empty.otherwise(r1), r1)
        AssertEqual(r1.otherwise(empty), r1)
    }
    
    func testOtherwiseCount() {
        let r1 = MakeRelation(
            ["id", "name"],
            [1,    "cat"])
        var r2 = MakeRelation(
            ["id", "name"])

        let r = r2.otherwise(r1)
        
        AssertEqual(r.count(), MakeRelation(["count"], [1]))
        
        r2.add(["id": 2, "name": "dog"])
        
        AssertEqual(r.count(), MakeRelation(["count"], [1]))
    }
    
    func testUnique() {
        let r1 = MakeRelation(
            ["id", "name", "type"],
            [1,    "cat",  "animal"],
            [2,    "dog",  "animal"],
            [3,    "corn", "plant"])
        
        AssertEqual(r1.unique("type", matching: "animal"),
                    MakeRelation(
                        ["id", "name", "type"]))
        
        let r2 = MakeRelation(
            ["id", "name", "type"],
            [1,    "cat",  "animal"],
            [2,    "dog",  "animal"],
            [3,    "pig",  "animal"])
        
        AssertEqual(r2.unique("type", matching: "animal"),
            MakeRelation(
                ["id", "name", "type"],
                [1,    "cat",  "animal"],
                [2,    "dog",  "animal"],
                [3,    "pig",  "animal"]))
    }
    
    func testAsyncRows() {
        let r1 = MakeRelation(
            ["first", "last", "pet"],
            ["Steve", "Smith", "cat"],
            ["Lisa", "Jobs", "cat"],
            ["Cindy", "Jobs", "dog"],
            ["Allen", "Jones", "dog"])
        var r2 = MakeRelation(
            ["first", "last", "pet"])
        
        let runloop = CFRunLoopGetCurrent()
        
        let group = dispatch_group_create()
        dispatch_group_enter(group)
        r1.asyncAllRows({ result in
            guard let rows = result.ok else { return XCTAssertNil(result.err) }
            for row in rows {
                r2.add(row)
            }
            dispatch_group_leave(group)
            CFRunLoopStop(runloop)
        })
        CFRunLoopRun()
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER)
        AssertEqual(r1, r2)
        
        r2 = MakeRelation(
            ["first", "last", "pet"])
        dispatch_group_enter(group)
        r1.asyncAllRows({ result in
            guard let rows = result.ok else { return XCTAssertNil(result.err) }
            for row in rows {
                r2.add(row)
            }
            dispatch_group_leave(group)
            CFRunLoopStop(runloop)
        })
        CFRunLoopRun()
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER)
        AssertEqual(r1, r2)
    }
    
    func testAsyncWorkSharing() {
        let r1 = MakeRelation(["n"], [1])
        let r2 = MakeRelation(["n"], [2])
        
        var r1Count = 0
        let r1Aggregate = IntermediateRelation(op: .Aggregate("n", nil, { (_, _) in
            r1Count += 1
            return .Ok(3)
        }), operands: [r1])
        
        var r2Count = 0
        let r2Aggregate = IntermediateRelation(op: .Aggregate("n", nil, { (_, _) in
            r2Count += 1
            return .Ok(4)
        }), operands: [r2])
        
        let out1 = r1Aggregate.union(r2Aggregate)
        let out2 = r1Aggregate.intersection(r2Aggregate)
        let out3 = r1Aggregate.difference(r2Aggregate)
        
        let group = dispatch_group_create()
        
        dispatch_group_enter(group)
        out1.asyncAllRows({ result in
            defer { dispatch_group_leave(group) }
            guard let rows = result.ok else { return XCTAssertNil(result.err) }
            XCTAssertEqual(rows, [["n": 3], ["n": 4]])
        })
        
        dispatch_group_enter(group)
        out2.asyncAllRows({ result in
            defer { dispatch_group_leave(group) }
            guard let rows = result.ok else { return XCTAssertNil(result.err) }
            XCTAssertEqual(rows, [])
        })
        
        dispatch_group_enter(group)
        out3.asyncAllRows({ result in
            defer { dispatch_group_leave(group) }
            guard let rows = result.ok else { return XCTAssertNil(result.err) }
            XCTAssertEqual(rows, [["n": 3]])
        })
        
        dispatch_group_notify(group, dispatch_get_main_queue(), {
            CFRunLoopStop(CFRunLoopGetCurrent())
        })
        CFRunLoopRun()
        
        XCTAssertEqual(r1Count, 1)
        XCTAssertEqual(r2Count, 1)
    }
    
    func testNotSelect() {
        let FLIGHTS = MakeRelation(
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
    
    func testComplexCount() {
        let sqliteDB = makeDB().db.sqliteDatabase
        let db = TransactionalDatabase(sqliteDB)
        func createRelation(name: String, _ scheme: Scheme) -> MutableRelation {
            let createResult = sqliteDB.createRelation(name, scheme: scheme)
            precondition(createResult.ok != nil)
            return db[name]
        }
        
        var collections = createRelation("collection", ["id", "type", "name", "parent", "order"])
        var objects = createRelation("object", ["id", "type", "name", "coll_id", "order"])
        var selectedCollectionID = createRelation("selected_collection", ["coll_id"])
        var selectedInspectorItemIDs = createRelation("selected_inspector_item", ["item_id"])
        
        let selectedCollection = selectedCollectionID
            .equijoin(collections, matching: ["coll_id": "id"])
            .project(["id", "type", "name"])
        
        let inspectorCollectionItems = selectedCollection
            .join(MakeRelation(["parent", "order"], [.NULL, 5.0]))
        let inspectorObjectItems = selectedCollectionID
            .join(objects)
            .renameAttributes(["coll_id": "parent"])
        let inspectorItems = inspectorCollectionItems
            .union(inspectorObjectItems)
        let selectedInspectorItems = selectedInspectorItemIDs
            .equijoin(inspectorItems, matching: ["item_id": "id"])
            .project(["id", "type", "name"])
        
        let selectedItems = selectedInspectorItems.otherwise(selectedCollection)
        let selectedItemTypes = selectedItems.project(["type"])
        let selectedItemsCount = selectedItems.count()
        
        var id: Int64 = 1
        var order: Double = 1.0
        
        func addCollection(name: String) {
            let row: Row = [
                "id": RelationValue(id),
                "type": "coll",
                "name": RelationValue(name),
                "parent": .NULL,
                "order": RelationValue(order)
            ]
            collections.add(row)
            id += 1
            order += 1.0
        }
        
        func addObject(name: String) {
            let row: Row = [
                "id": RelationValue(id),
                "type": "obj",
                "name": RelationValue(name),
                "coll_id": 1,
                "order": RelationValue(order)
            ]
            objects.add(row)
            id += 1
            order += 1.0
        }
        
        addCollection("Page1")
        addCollection("Page2")
        addObject("Obj1")
        addObject("Obj2")
        
        selectedInspectorItemIDs.delete(true)
        selectedCollectionID.add(["coll_id": 1])
        
        AssertEqual(selectedItems,
                    MakeRelation(
                        ["id", "name", "type"],
                        [1, "Page1", "coll"]))
        AssertEqual(selectedItemsCount,
                    MakeRelation(
                        ["count"],
                        [1]))
        
        selectedInspectorItemIDs.delete(true)
        selectedInspectorItemIDs.add(["item_id": 1])
        
        AssertEqual(selectedItems,
                    MakeRelation(
                        ["id", "name", "type"],
                        [1, "Page1", "coll"]))
        AssertEqual(selectedItemsCount,
                    MakeRelation(
                        ["count"],
                        [1]))
    }
    
    func testHugeRelationGraphPerformance() {
        let base = MakeRelation(["A"])
        
        func unionAllPairs(relations: [Relation]) -> [Relation] {
            var result: [Relation] = []
            for (indexA, a) in relations.enumerate() {
                for b in relations[indexA ..< relations.endIndex] {
                    result.append(a.union(b))
                }
            }
            return result
        }
        
        func unionAdjacentPairs(relations: [Relation]) -> [Relation] {
            var result: [Relation] = []
            for i in 0.stride(to: relations.endIndex - 1, by: 2) {
                result.append(relations[i].union(relations[i + 1]))
            }
            if relations.count % 2 != 0 {
                result.append(relations.first!.union(relations.last!))
            }
            return result
        }
        
        let level2 = unionAllPairs([base, base, base])
        let level3 = unionAllPairs(level2)
        let level4 = unionAllPairs(level3)
        let level5 = unionAllPairs(level4)
        var bringTogether = level5
        while bringTogether.count > 1 {
            bringTogether = unionAdjacentPairs(bringTogether)
        }
        let final = bringTogether[0]
        
        measureBlock({
            AssertEqual(nil, final)
        })
    }
    
    func testOr() {
        let concrete = MakeRelation(
            ["name", "kind"],
            ["Earth", "planet"],
            ["Steve", "person"],
            ["Tim", "plant"]
        )
        
        AssertEqual(concrete.select(Attribute("kind") *== "planet" *|| Attribute("name") *== "Tim"),
                    MakeRelation(
                        ["name", "kind"],
                        ["Earth", "planet"],
                        ["Tim", "plant"]))
        
        let sqliteDB = makeDB().db.sqliteDatabase
        let sqliteRelation = sqliteDB.createRelation("whatever", scheme: concrete.scheme).ok!
        for row in concrete.rows() {
            let result = sqliteRelation.add(row.ok!)
            XCTAssertNil(result.err)
        }
        AssertEqual(sqliteRelation.select(Attribute("kind") *== "planet" *|| Attribute("name") *== "Tim"),
                    MakeRelation(
                        ["name", "kind"],
                        ["Earth", "planet"],
                        ["Tim", "plant"]))
    }
    
    func testGlob() {
        let concrete = MakeRelation(
            ["name", "kind"],
            ["Earth", "planet"],
            ["Steve", "person"],
            ["Tim", "plant"]
        )
        
        AssertEqual(concrete.select(SelectExpressionBinaryOperator(lhs: Attribute("kind"), op: GlobComparator(), rhs: "pl*")),
                    MakeRelation(
                        ["name", "kind"],
                        ["Earth", "planet"],
                        ["Tim", "plant"]))
        AssertEqual(concrete.select(SelectExpressionBinaryOperator(lhs: Attribute("kind"), op: GlobComparator(), rhs: "plan*t")),
                    MakeRelation(
                        ["name", "kind"],
                        ["Earth", "planet"],
                        ["Tim", "plant"]))
        AssertEqual(concrete.select(SelectExpressionBinaryOperator(lhs: Attribute("kind"), op: GlobComparator(), rhs: "p?????")),
                    MakeRelation(
                        ["name", "kind"],
                        ["Earth", "planet"],
                        ["Steve", "person"]))
        AssertEqual(concrete.select(SelectExpressionBinaryOperator(lhs: Attribute("kind"), op: GlobComparator(), rhs: "*r*")),
                    MakeRelation(
                        ["name", "kind"],
                        ["Steve", "person"]))
        
        let sqliteDB = makeDB().db.sqliteDatabase
        let sqliteRelation = sqliteDB.createRelation("whatever", scheme: concrete.scheme).ok!
        for row in concrete.rows() {
            let result = sqliteRelation.add(row.ok!)
            XCTAssertNil(result.err)
        }
        AssertEqual(sqliteRelation.select(SelectExpressionBinaryOperator(lhs: Attribute("kind"), op: GlobComparator(), rhs: "pl*")),
                    MakeRelation(
                        ["name", "kind"],
                        ["Earth", "planet"],
                        ["Tim", "plant"]))
        AssertEqual(sqliteRelation.select(SelectExpressionBinaryOperator(lhs: Attribute("kind"), op: GlobComparator(), rhs: "plan*t")),
                    MakeRelation(
                        ["name", "kind"],
                        ["Earth", "planet"],
                        ["Tim", "plant"]))
        AssertEqual(sqliteRelation.select(SelectExpressionBinaryOperator(lhs: Attribute("kind"), op: GlobComparator(), rhs: "p?????")),
                    MakeRelation(
                        ["name", "kind"],
                        ["Earth", "planet"],
                        ["Steve", "person"]))
        AssertEqual(sqliteRelation.select(SelectExpressionBinaryOperator(lhs: Attribute("kind"), op: GlobComparator(), rhs: "*r*")),
                    MakeRelation(
                        ["name", "kind"],
                        ["Steve", "person"]))
    }
    
    func testConcurrentConcreteIteration() {
        var r1 = ConcreteRelation(scheme: ["n"])
        var r2 = ConcreteRelation(scheme: ["w"])
        
        for i: Int64 in 1...10 {
            r1.add(["n": .Integer(i)])
        }
        
        r2.add(["w": "teapot"])
        r2.add(["w": "dome"])
        r2.add(["w": "scandal"])
        r2.add(["w": "walrus"])
        r2.add(["w": "businessmanlike"])
        
        let joined = r1.join(r2)
        
        dispatch_apply(1000, dispatch_get_global_queue(0, 0), { _ in
            for row in joined.rows() {
                XCTAssertNil(row.err)
            }
        })
    }
    
    func testConcurrentSQLiteIteration() {
        let db = makeDB().db.sqliteDatabase
        
        let r1 = db.getOrCreateRelation("numbers", scheme: ["n"]).ok!
        let r2 = db.getOrCreateRelation("words", scheme: ["w"]).ok!
        
        for i: Int64 in 1...10 {
            r1.add(["n": .Integer(i)])
        }
        
        r2.add(["w": "teapot"])
        r2.add(["w": "dome"])
        r2.add(["w": "scandal"])
        r2.add(["w": "walrus"])
        r2.add(["w": "businessmanlike"])
        
        let joined = r1.join(r2)
        
        dispatch_apply(1000, dispatch_get_global_queue(0, 0), { _ in
            for row in joined.rows() {
                XCTAssertNil(row.err)
            }
        })
    }
}
