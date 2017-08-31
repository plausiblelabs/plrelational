//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import PLRelational

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
        let FLIGHTS = MakeRelation(
            ["NUMBER", "FROM",   "TO",          "DEPARTS", "ARRIVES"],
            ["83",     "JFK",    "O'Hare",      "11:30a",  "1:43p"],
            ["84",     "O'Hare", "JFK",         "3:00p",   "5:55p"],
            ["109",    "JFK",    "Los Angeles", "9:50p",   "2:52a"],
            ["213",    "JFK",    "Boston",      "11:43a",  "12:45p"],
            ["214",    "Boston", "O'Hare",      "2:20p",   "3:12p"]
        )
        
        _ = FLIGHTS.add(["NUMBER": "117", "FROM": "Atlanta", "TO": "Boston", "DEPARTS": "10:05p", "ARRIVES": "12:43a"])
        AssertEqual(FLIGHTS,
                    MakeRelation(
                        ["NUMBER", "FROM",   "TO",          "DEPARTS", "ARRIVES"],
                        ["83",     "JFK",    "O'Hare",      "11:30a",  "1:43p"],
                        ["84",     "O'Hare", "JFK",         "3:00p",   "5:55p"],
                        ["109",    "JFK",    "Los Angeles", "9:50p",   "2:52a"],
                        ["213",    "JFK",    "Boston",      "11:43a",  "12:45p"],
                        ["214",    "Boston", "O'Hare",      "2:20p",   "3:12p"],
                        ["117",    "Atlanta", "Boston",     "10:05p",  "12:43a"]))
        
        _ = FLIGHTS.delete(Attribute("NUMBER") *== "83")
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
        
        _ = FLIGHTS.update(Attribute("NUMBER") *== "109", newValues: ["DEPARTS": "9:40p", "ARRIVES": "2:42a"])
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
            )
        
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
    
    func testLeftOuterJoin() {
        let employees = MakeRelation(
            ["emp_id", "emp_name", "dept_name"],
            [1, "Alice", "Sales"],
            [2, "Bob", "Finance"],
            [3, "Carlos", "Production"],
            [4, "Donald", "Production"])
        
        let departments = MakeRelation(
            ["dept_name", "manager_id"],
            ["Sales", 1],
            ["Production", 3])
        
        let joined = employees.leftOuterJoin(departments)
        
        AssertEqual(
            joined,
            MakeRelation(
                ["emp_id", "emp_name", "dept_name", "manager_id"],
                [1, "Alice", "Sales", 1],
                [2, "Bob", "Finance", .null],
                [3, "Carlos", "Production", 3],
                [4, "Donald", "Production", 3]))
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
        AssertEqual(times.select(SelectExpressionBinaryOperator(lhs: Attribute("ARRIVES"), op: LTComparator(), rhs: RelationValue.integer(1300))),
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
        let r2 = MakeRelation(
            ["id", "name"])

        let r = r2.otherwise(r1)
        
        AssertEqual(r.count(), MakeRelation(["count"], [1]))
        
        _ = r2.add(["id": 2, "name": "dog"])
        
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
        
        let group = DispatchGroup()
        group.enter()
        r1.asyncAllRows({ result in
            XCTAssertTrue(runloop === CFRunLoopGetCurrent())
            guard let rows = result.ok else { return XCTAssertNil(result.err) }
            for row in rows {
                _ = r2.add(row)
            }
            group.leave()
            CFRunLoopStop(runloop)
        })
        CFRunLoopRun()
        _ = group.wait(timeout: DispatchTime.distantFuture)
        AssertEqual(r1, r2)
        
        r2 = MakeRelation(
            ["first", "last", "pet"])
        group.enter()
        r1.asyncAllRows({ result in
            guard let rows = result.ok else { return XCTAssertNil(result.err) }
            for row in rows {
                _ = r2.add(row)
            }
            group.leave()
            CFRunLoopStop(runloop)
        })
        CFRunLoopRun()
        _ = group.wait(timeout: DispatchTime.distantFuture)
        AssertEqual(r1, r2)
    }
    
    func testAsyncRowsPostprocessing() {
        let r = MakeRelation(["n"])
        for i: Int64 in 0 ..< 20 {
            _ = r.add(["n": .integer(i)])
        }
        
        let runloop = CFRunLoopGetCurrent()
        
        var output: [Row] = []
        
        let group = DispatchGroup()
        group.enter()
        r.asyncAllRows(
            postprocessor: sortByAttribute("n"),
            completion: { result in
                XCTAssertTrue(runloop === CFRunLoopGetCurrent())
                guard let rows = result.ok else { return XCTAssertNil(result.err) }
                output = rows
                group.leave()
                CFRunLoopStop(runloop)
            }
        )
        CFRunLoopRun()
        _ = group.wait(timeout: DispatchTime.distantFuture)
        
        XCTAssertEqual((0 ..< 20).map({ ["n": .integer($0)] }), output)
    }

    func testAsyncWorkSharing() {
        let r1 = MakeRelation(["n"], [1])
        let r2 = MakeRelation(["n"], [2])
        
        var r1Count = 0
        let r1Aggregate = IntermediateRelation(op: .aggregate("n", nil, { (_, _) in
            r1Count += 1
            return .Ok(3)
        }), operands: [r1])
        
        var r2Count = 0
        let r2Aggregate = IntermediateRelation(op: .aggregate("n", nil, { (_, _) in
            r2Count += 1
            return .Ok(4)
        }), operands: [r2])
        
        let out1 = r1Aggregate.union(r2Aggregate)
        let out2 = r1Aggregate.intersection(r2Aggregate)
        let out3 = r1Aggregate.difference(r2Aggregate)
        
        let group = DispatchGroup()
        
        group.enter()
        out1.asyncAllRows({ result in
            defer { group.leave() }
            guard let rows = result.ok else { return XCTAssertNil(result.err) }
            XCTAssertEqual(rows, [["n": 3], ["n": 4]])
        })
        
        group.enter()
        out2.asyncAllRows({ result in
            defer { group.leave() }
            guard let rows = result.ok else { return XCTAssertNil(result.err) }
            XCTAssertEqual(rows, [])
        })
        
        group.enter()
        out3.asyncAllRows({ result in
            defer { group.leave() }
            guard let rows = result.ok else { return XCTAssertNil(result.err) }
            XCTAssertEqual(rows, [["n": 3]])
        })
        
        group.notify(queue: DispatchQueue.main, execute: {
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
        let sqliteDB = makeDB().db
        let db = TransactionalDatabase(sqliteDB)
        func createRelation(_ name: String, _ scheme: Scheme) -> MutableRelation {
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
            .join(MakeRelation(["parent", "order"], [.null, 5.0]))
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
        
        func addCollection(_ name: String) {
            let row: Row = [
                "id": RelationValue(id),
                "type": "coll",
                "name": RelationValue(name),
                "parent": .null,
                "order": RelationValue(order)
            ]
            _ = collections.add(row)
            id += 1
            order += 1.0
        }
        
        func addObject(_ name: String) {
            let row: Row = [
                "id": RelationValue(id),
                "type": "obj",
                "name": RelationValue(name),
                "coll_id": 1,
                "order": RelationValue(order)
            ]
            _ = objects.add(row)
            id += 1
            order += 1.0
        }
        
        addCollection("Page1")
        addCollection("Page2")
        addObject("Obj1")
        addObject("Obj2")
        
        _ = selectedInspectorItemIDs.delete(true)
        _ = selectedCollectionID.add(["coll_id": 1])
        
        AssertEqual(selectedItems,
                    MakeRelation(
                        ["id", "name", "type"],
                        [1, "Page1", "coll"]))
        AssertEqual(selectedItemsCount,
                    MakeRelation(
                        ["count"],
                        [1]))
        
        _ = selectedInspectorItemIDs.delete(true)
        _ = selectedInspectorItemIDs.add(["item_id": 1])
        
        AssertEqual(selectedItems,
                    MakeRelation(
                        ["id", "name", "type"],
                        [1, "Page1", "coll"]))
        AssertEqual(selectedItemsCount,
                    MakeRelation(
                        ["count"],
                        [1]))
    }
    
    func testDeleteWithJoin() {
        let sqliteDB = makeDB().db
        let db = TransactionalDatabase(sqliteDB)
        func createRelation(_ name: String, _ scheme: Scheme) -> MutableRelation {
            let createResult = sqliteDB.createRelation(name, scheme: scheme)
            precondition(createResult.ok != nil)
            return db[name]
        }
        
        let objects = createRelation("object", ["id", "name"])
        let selectedObjectID = createRelation("selected_object", ["id"])
        
        let selectedObject = selectedObjectID.join(objects)
        
        _ = objects.add(["id": 1, "name": "One"])
        _ = objects.add(["id": 2, "name": "Two"])
        
        AssertEqual(selectedObject,
                    MakeRelation(
                        ["id", "name"]))

        _ = selectedObjectID.add(["id": 1])
        
        AssertEqual(selectedObject,
                    MakeRelation(
                        ["id", "name"],
                        [1, "One"]))
        
        _ = objects.delete(Attribute("id") *== 1)
        
        AssertEqual(selectedObject,
                    MakeRelation(
                        ["id", "name"]))
    }
    
    func testHugeRelationGraphPerformance() {
        let base = MakeRelation(["A"])
        
        func unionAllPairs(_ relations: [Relation]) -> [Relation] {
            var result: [Relation] = []
            for (indexA, a) in relations.enumerated() {
                for b in relations[indexA ..< relations.endIndex] {
                    result.append(a.union(b))
                }
            }
            return result
        }
        
        func unionAdjacentPairs(_ relations: [Relation]) -> [Relation] {
            var result: [Relation] = []
            for i in stride(from: 0, to: relations.endIndex - 1, by: 2) {
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
        
        measure({
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
        
        let sqliteDB = makeDB().db
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
        
        let sqliteDB = makeDB().db
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
            _ = r1.add(["n": .integer(i)])
        }
        
        _ = r2.add(["w": "teapot"])
        _ = r2.add(["w": "dome"])
        _ = r2.add(["w": "scandal"])
        _ = r2.add(["w": "walrus"])
        _ = r2.add(["w": "businessmanlike"])
        
        let joined = r1.join(r2)
        
        DispatchQueue.concurrentPerform(iterations: 1000, execute: { _ in
            for row in joined.rows() {
                XCTAssertNil(row.err)
            }
        })
    }
    
    func testConcurrentSQLiteIteration() {
        let db = makeDB().db
        
        let r1 = db.getOrCreateRelation("numbers", scheme: ["n"]).ok!
        let r2 = db.getOrCreateRelation("words", scheme: ["w"]).ok!
        
        for i: Int64 in 1...10 {
            _ = r1.add(["n": .integer(i)])
        }
        
        _ = r2.add(["w": "teapot"])
        _ = r2.add(["w": "dome"])
        _ = r2.add(["w": "scandal"])
        _ = r2.add(["w": "walrus"])
        _ = r2.add(["w": "businessmanlike"])
        
        let joined = r1.join(r2)
        
        DispatchQueue.concurrentPerform(iterations: 1000, execute: { _ in
            for row in joined.rows() {
                XCTAssertNil(row.err)
            }
        })
    }
    
    func testTreeDelete() {
        let r = MemoryTableRelation.copyRelation(
            MakeRelation(
                ["id", "parent"],
                [1, .null],
                [2, .null],
                [3, .null],
                [4, .null],
                [10, 1],
                [11, 1],
                [12, 1],
                [100, 10],
                [101, 10],
                [110, 11],
                [1100, 110],
                [20, 2],
                [21, 2],
                [22, 2],
                [200, 20],
                [201, 20],
                [210, 21],
                [2100, 210],
                [30, 3],
                [31, 3],
                [32, 3],
                [300, 30],
                [301, 30],
                [310, 31],
                [3100, 310],
                [40, 4],
                [41, 4],
                [42, 4],
                [400, 40],
                [401, 40],
                [410, 41],
                [4100, 410]
        )).ok!
        
        class Observer: AsyncRelationChangeCoalescedObserver {
            let group: DispatchGroup
            
            var changes: RowChange?
            
            init(group: DispatchGroup) {
                self.group = group
            }
            
            func relationWillChange(_ relation: Relation) {
                XCTAssertNil(changes)
            }
            
            func relationDidChange(_ relation: Relation, result: Result<RowChange, RelationError>) {
                XCTAssertNil(result.err)
                self.changes = result.ok
                group.leave()
            }
        }
        
        let group = DispatchGroup()
        let observer = Observer(group: group)
        
        group.enter()
        let remover = r.addAsyncObserver(observer)
        
        group.enter()
        r.treeDelete(Attribute("id") *== 1 *|| Attribute("id") *== 2 *|| Attribute("id") *== 30, parentAttribute: "id", childAttribute: "parent", completionCallback: { result in
            XCTAssertNil(result.err)
            group.leave()
        })
        
        let runloop = CFRunLoopGetCurrent()!
        group.notify(queue: DispatchQueue.global(), execute: { runloop.async({ CFRunLoopStop(runloop) }) })
        CFRunLoopRun()
        
        let expectedRemaining = MakeRelation(
            ["id", "parent"],
            [3, .null],
            [4, .null],
            [31, 3],
            [32, 3],
            [310, 31],
            [3100, 310],
            [40, 4],
            [41, 4],
            [42, 4],
            [400, 40],
            [401, 40],
            [410, 41],
            [4100, 410]
        )
        
        let expectedRemoved = MakeRelation(
            ["id", "parent"],
            [1, .null],
            [2, .null],
            [10, 1],
            [11, 1],
            [12, 1],
            [100, 10],
            [101, 10],
            [110, 11],
            [1100, 110],
            [20, 2],
            [21, 2],
            [22, 2],
            [200, 20],
            [201, 20],
            [210, 21],
            [2100, 210],
            [30, 3],
            [300, 30],
            [301, 30]
        ).values
        
        AssertEqual(r, expectedRemaining)
        XCTAssertNotNil(observer.changes)
        XCTAssertEqual(observer.changes!.added, [])
        XCTAssertEqual(observer.changes!.removed, expectedRemoved)
        
        remover()
    }

    func testCascadingDelete() {
        let r1 = MakeRelation(
            ["id", "parent"],
            [1, .null],
            [2, .null],
            [3, .null],
            [4, .null],
            [10, 1],
            [11, 1],
            [12, 1],
            [100, 10],
            [101, 10],
            [110, 11],
            [1100, 110],
            [20, 2],
            [21, 2],
            [22, 2],
            [200, 20],
            [201, 20],
            [210, 21],
            [2100, 210],
            [30, 3],
            [31, 3],
            [32, 3],
            [300, 30],
            [301, 30],
            [310, 31],
            [3100, 310],
            [40, 4],
            [41, 4],
            [42, 4],
            [400, 40],
            [401, 40],
            [410, 41],
            [4100, 410]
        )
        let r2 = MakeRelation(
            ["id", "name"],
            [1, "Steve"],
            [2, "Bill"],
            [3, "John"],
            [4, "Ebenezer"],
            [5, "Tim"],
            [100, "Timmy"],
            [200, "Timothy"],
            [300, "Thomas"],
            [400, "Thompson"]
        )
        let r3 = MemoryTableRelation.copyRelation(r2.project(["name"])).ok!
        
        class Observer: AsyncRelationChangeCoalescedObserver {
            let group: DispatchGroup
            
            var changes: RowChange?
            
            init(group: DispatchGroup) {
                self.group = group
            }
            
            func relationWillChange(_ relation: Relation) {
                XCTAssertNil(changes)
            }
            
            func relationDidChange(_ relation: Relation, result: Result<RowChange, RelationError>) {
                XCTAssertNil(result.err)
                self.changes = result.ok
                group.leave()
            }
        }
        
        let group = DispatchGroup()

        group.enter()
        let observer1 = Observer(group: group)
        let remover1 = r1.addAsyncObserver(observer1)
        
        group.enter()
        let observer2 = Observer(group: group)
        let remover2 = r2.addAsyncObserver(observer2)
        
        group.enter()
        let observer3 = Observer(group: group)
        let remover3 = r3.addAsyncObserver(observer3)
        
        group.enter()
        r1.cascadingDelete(
            Attribute("id") *== 1 *|| Attribute("id") *== 2 *|| Attribute("id") *== 30,
            affectedRelations: [r1, r2, r3],
            cascade: { (relation, row) in
                if relation === r1 {
                    return [
                        (r1, Attribute("parent") *== row["id"]),
                        (r2, Attribute("id") *== row["id"])
                    ]
                } else if relation === r2 {
                    return [(r3, Attribute("name") *== row["name"])]
                } else {
                    return []
                }
            },
            completionCallback: { result in
                XCTAssertNil(result.err)
                group.leave()
            }
        )
        
        let runloop = CFRunLoopGetCurrent()!
        group.notify(queue: DispatchQueue.global(), execute: { runloop.async({ CFRunLoopStop(runloop) }) })
        CFRunLoopRun()
        
        let expectedRemaining1 = MakeRelation(
            ["id", "parent"],
            [3, .null],
            [4, .null],
            [31, 3],
            [32, 3],
            [310, 31],
            [3100, 310],
            [40, 4],
            [41, 4],
            [42, 4],
            [400, 40],
            [401, 40],
            [410, 41],
            [4100, 410]
        )
        
        let expectedRemoved1 = MakeRelation(
            ["id", "parent"],
            [1, .null],
            [2, .null],
            [10, 1],
            [11, 1],
            [12, 1],
            [100, 10],
            [101, 10],
            [110, 11],
            [1100, 110],
            [20, 2],
            [21, 2],
            [22, 2],
            [200, 20],
            [201, 20],
            [210, 21],
            [2100, 210],
            [30, 3],
            [300, 30],
            [301, 30]
            ).values
        
        AssertEqual(r1, expectedRemaining1)
        XCTAssertNotNil(observer1.changes)
        XCTAssertEqual(observer1.changes!.added, [])
        XCTAssertEqual(observer1.changes!.removed, expectedRemoved1)
        
        let expectedRemaining2 = MakeRelation(
            ["id", "name"],
            [3, "John"],
            [4, "Ebenezer"],
            [5, "Tim"],
            [400, "Thompson"]
        )
        
        let expectedRemoved2 = MakeRelation(
            ["id", "name"],
            [1, "Steve"],
            [2, "Bill"],
            [100, "Timmy"],
            [200, "Timothy"],
            [300, "Thomas"]
            ).values
        
        AssertEqual(r2, expectedRemaining2)
        XCTAssertNotNil(observer2.changes)
        XCTAssertEqual(observer2.changes!.added, [])
        XCTAssertEqual(observer2.changes!.removed, expectedRemoved2)
        
        let expectedRemaining3 = MakeRelation(
            ["name"],
            ["John"],
            ["Ebenezer"],
            ["Tim"],
            ["Thompson"]
        )
        
        let expectedRemoved3 = MakeRelation(
            ["name"],
            ["Steve"],
            ["Bill"],
            ["Timmy"],
            ["Timothy"],
            ["Thomas"]
            ).values
        
        AssertEqual(r3, expectedRemaining3)
        XCTAssertNotNil(observer3.changes)
        XCTAssertEqual(observer3.changes!.added, [])
        XCTAssertEqual(observer3.changes!.removed, expectedRemoved3)
        
        remover1()
        remover2()
        remover3()
    }
    
    func testCascadingDeleteAndUpdate() {
        let r1 = MakeRelation(
            ["id", "parent"],
            [1, .null],
            [2, .null],
            [3, .null],
            [4, .null],
            [10, 1],
            [11, 1],
            [12, 1],
            [100, 10],
            [101, 10],
            [110, 11],
            [1100, 110],
            [20, 2],
            [21, 2],
            [22, 2],
            [200, 20],
            [201, 20],
            [210, 21],
            [2100, 210],
            [30, 3],
            [31, 3],
            [32, 3],
            [300, 30],
            [301, 30],
            [310, 31],
            [3100, 310],
            [40, 4],
            [41, 4],
            [42, 4],
            [400, 40],
            [401, 40],
            [410, 41],
            [4100, 410]
        )
        let r2 = MakeRelation(
            ["id", "name"],
            [1, "Steve"],
            [2, "Bill"],
            [3, "John"],
            [4, "Ebenezer"],
            [5, "Tim"],
            [100, "Timmy"],
            [200, "Timothy"],
            [300, "Thomas"],
            [400, "Thompson"]
        )
        let r3 = MemoryTableRelation.copyRelation(r2.project(["name"])).ok!
        let r4 = MakeRelation(["id"], [30])
        
        class Observer: AsyncRelationChangeCoalescedObserver {
            let group: DispatchGroup
            
            var changes: RowChange?
            
            init(group: DispatchGroup) {
                self.group = group
            }
            
            func relationWillChange(_ relation: Relation) {
                XCTAssertNil(changes)
            }
            
            func relationDidChange(_ relation: Relation, result: Result<RowChange, RelationError>) {
                XCTAssertNil(result.err)
                self.changes = result.ok
                group.leave()
            }
        }
        
        let group = DispatchGroup()
        
        group.enter()
        let observer1 = Observer(group: group)
        let remover1 = r1.addAsyncObserver(observer1)
        
        group.enter()
        let observer2 = Observer(group: group)
        let remover2 = r2.addAsyncObserver(observer2)
        
        group.enter()
        let observer3 = Observer(group: group)
        let remover3 = r3.addAsyncObserver(observer3)
        
        group.enter()
        r1.cascadingDelete(
            Attribute("id") *== 1 *|| Attribute("id") *== 2 *|| Attribute("id") *== 30,
            affectedRelations: [r1, r2, r3, r4],
            cascade: { (relation, row) in
                if relation === r1 {
                    return [
                        (r1, Attribute("parent") *== row["id"]),
                        (r2, Attribute("id") *== row["id"])
                    ]
                } else if relation === r2 {
                    return [(r3, Attribute("name") *== row["name"])]
                } else {
                    return []
                }
        },
            update: { (relation, row) in
                if relation === r1 {
                    let id = Attribute("id")
                    let deletedID = row["id"]
                    let matched = r4.select(id *== deletedID)
                    let lower = r1.select(id *<= deletedID).project(id).max(id)
                    let higher = r1.select(id *> deletedID).project(id).min(id)
                    let newCurrentID = lower.otherwise(higher)
                    return [CascadingUpdate(relation: matched, query: true, attributes: [id], fromRelation: newCurrentID)]
                } else {
                    return []
                }
        },
            completionCallback: { result in
                XCTAssertNil(result.err)
                group.leave()
        }
        )
        
        let runloop = CFRunLoopGetCurrent()!
        group.notify(queue: DispatchQueue.global(), execute: { runloop.async({ CFRunLoopStop(runloop) }) })
        CFRunLoopRun()
        
        let expectedRemaining1 = MakeRelation(
            ["id", "parent"],
            [3, .null],
            [4, .null],
            [31, 3],
            [32, 3],
            [310, 31],
            [3100, 310],
            [40, 4],
            [41, 4],
            [42, 4],
            [400, 40],
            [401, 40],
            [410, 41],
            [4100, 410]
        )
        
        let expectedRemoved1 = MakeRelation(
            ["id", "parent"],
            [1, .null],
            [2, .null],
            [10, 1],
            [11, 1],
            [12, 1],
            [100, 10],
            [101, 10],
            [110, 11],
            [1100, 110],
            [20, 2],
            [21, 2],
            [22, 2],
            [200, 20],
            [201, 20],
            [210, 21],
            [2100, 210],
            [30, 3],
            [300, 30],
            [301, 30]
            ).values
        
        AssertEqual(r1, expectedRemaining1)
        XCTAssertNotNil(observer1.changes)
        XCTAssertEqual(observer1.changes!.added, [])
        XCTAssertEqual(observer1.changes!.removed, expectedRemoved1)
        
        let expectedRemaining2 = MakeRelation(
            ["id", "name"],
            [3, "John"],
            [4, "Ebenezer"],
            [5, "Tim"],
            [400, "Thompson"]
        )
        
        let expectedRemoved2 = MakeRelation(
            ["id", "name"],
            [1, "Steve"],
            [2, "Bill"],
            [100, "Timmy"],
            [200, "Timothy"],
            [300, "Thomas"]
            ).values
        
        AssertEqual(r2, expectedRemaining2)
        XCTAssertNotNil(observer2.changes)
        XCTAssertEqual(observer2.changes!.added, [])
        XCTAssertEqual(observer2.changes!.removed, expectedRemoved2)
        
        let expectedRemaining3 = MakeRelation(
            ["name"],
            ["John"],
            ["Ebenezer"],
            ["Tim"],
            ["Thompson"]
        )
        
        let expectedRemoved3 = MakeRelation(
            ["name"],
            ["Steve"],
            ["Bill"],
            ["Timmy"],
            ["Timothy"],
            ["Thomas"]
            ).values
        
        AssertEqual(r3, expectedRemaining3)
        XCTAssertNotNil(observer3.changes)
        XCTAssertEqual(observer3.changes!.added, [])
        XCTAssertEqual(observer3.changes!.removed, expectedRemoved3)
        
        AssertEqual(r4, MakeRelation(["id"], [4]))
        
        remover1()
        remover2()
        remover3()
    }
    
    func testCodeDump() {
        let r1 = MakeRelation(
            ["name", "age"],
            ["Steve", 42],
            ["Bob", 18])
        let r2 = MakeRelation(
            ["name", "age"],
            ["Jane", 20],
            ["Sara", 55])
        let r3 = r1.union(r2)
        let r4 = r3.intersection(r1)
        let r5 = r4.difference(r2)
        let r6 = r5.project(["name"])
        let r7 = r6.select(Attribute("name") *== "Jane")
        let r8 = r7.mutableSelect(Attribute("name") *== "Jane")
        let r9 = r8.equijoin(r1, matching: ["name": "name"])
        let r10 = r9.renameAttributes(["name": "NAME"])
        let r11 = r10.withUpdate(["NAME": "Jaaane"])
        let r12 = r11.max("NAME")
        let r13 = r12.otherwise(r12)
        let r14 = r13.unique("NAME", matching: "Jaaane")
        //r14.dumpAsCode()
        _ = r14
    }
}
