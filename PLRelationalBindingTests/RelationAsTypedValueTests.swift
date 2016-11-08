//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import PLRelational
@testable import PLRelationalBinding

class RelationAsTypedValueTests: BindingTestCase {
    
    func testAllValues() {
        let empty = MakeRelation(
            ["id", "name"])
        
        let r = MakeRelation(
            ["id", "name"],
            [1,    "cat"],
            [2,    "dog"],
            [3,    "fish"])
        
        let rvset = Set([RelationValue("cat"), RelationValue("dog"), RelationValue("fish")])
        
        XCTAssertEqual(empty.project(["name"]).allValues(), Set())
        XCTAssertEqual(r.project(["name"]).allValues(), rvset)
        
        XCTAssertEqual(
            r.project(["name"]).allValues{
                let s: String = $0.get()!
                if s.characters.count <= 3 {
                    return "\(s)s"
                } else {
                    return nil
                }
            },
            Set(["cats", "dogs"]))
    }
    
    func testAnyValue() {
        let empty = MakeRelation(
            ["id", "name"])
        
        let r = MakeRelation(
            ["id", "name"],
            [1,    "cat"],
            [2,    "dog"],
            [3,    "fish"])
        
        let rvset = Set([RelationValue("cat"), RelationValue("dog"), RelationValue("fish")])
        let strset = Set(["cat", "dog", "fish"])
        
        XCTAssertNil(empty.project(["name"]).anyValue())
        XCTAssertTrue(rvset.contains(r.project(["name"]).anyValue()!))
        XCTAssertTrue(strset.contains(r.project(["name"]).anyValue{ v -> String? in v.get()! }!))
    }
    
    func testOneValue() {
        let empty = MakeRelation(
            ["id", "name", "friendly", "age", "pulse"])
        
        let one = MakeRelation(
            ["id", "name", "friendly", "age", "pulse"],
            [1,    "cat",  1,          5,     2.0],
            [2,    "cat",  1,          5,     2.0])
        
        let multi = MakeRelation(
            ["id", "name", "friendly", "age", "pulse"],
            [1,    "cat",  1,          5,     2.0],
            [2,    "dog",  0,          3,     1.0])
        
        let expr: SelectExpression = Attribute("id") *== 1
        let transform = { (row: Row) -> String? in "\(row["name"]):\(row["age"])" }
        XCTAssertNil(empty.oneValueFromRow(transform))
        XCTAssertEqual(one.select(expr).oneValueFromRow(transform), "cat:5")
        XCTAssertNil(multi.oneValueFromRow(transform))
        
        XCTAssertEqual(empty.oneValueFromRow(transform, orDefault: "default"), "default")
        XCTAssertEqual(one.select(expr).oneValueFromRow(transform, orDefault: "default"), "cat:5")
        XCTAssertEqual(multi.oneValueFromRow(transform, orDefault: "default"), "default")
        
        XCTAssertNil(empty.project(["name"]).oneValueOrNil())
        XCTAssertEqual(one.project(["name"]).oneValueOrNil(), RelationValue("cat"))
        XCTAssertNil(multi.project(["name"]).oneValueOrNil())
        
        XCTAssertEqual(empty.project(["name"]).oneString(), "")
        XCTAssertEqual(one.project(["name"]).oneString(), "cat")
        XCTAssertEqual(multi.project(["name"]).oneString(), "")
        
        XCTAssertNil(empty.project(["name"]).oneStringOrNil(), "")
        XCTAssertEqual(one.project(["name"]).oneStringOrNil(), "cat")
        XCTAssertNil(multi.project(["name"]).oneStringOrNil())
        
        XCTAssertEqual(empty.project(["friendly"]).oneBool(), false)
        XCTAssertEqual(one.project(["friendly"]).oneBool(), true)
        XCTAssertEqual(multi.project(["friendly"]).oneBool(), false)
        
        XCTAssertNil(empty.project(["friendly"]).oneBoolOrNil())
        XCTAssertEqual(one.project(["friendly"]).oneBoolOrNil(), true)
        XCTAssertNil(multi.project(["friendly"]).oneBoolOrNil())
        
        XCTAssertEqual(empty.project(["age"]).oneInteger(), 0)
        XCTAssertEqual(one.project(["age"]).oneInteger(), 5)
        XCTAssertEqual(multi.project(["age"]).oneInteger(), 0)
        
        XCTAssertNil(empty.project(["age"]).oneIntegerOrNil())
        XCTAssertEqual(one.project(["age"]).oneIntegerOrNil(), 5)
        XCTAssertNil(multi.project(["age"]).oneIntegerOrNil())
        
        XCTAssertEqual(empty.project(["pulse"]).oneDouble(), 0.0)
        XCTAssertEqual(one.project(["pulse"]).oneDouble(), 2.0)
        XCTAssertEqual(multi.project(["pulse"]).oneDouble(), 0.0)
        
        XCTAssertNil(empty.project(["pulse"]).oneDoubleOrNil())
        XCTAssertEqual(one.project(["pulse"]).oneDoubleOrNil(), 2.0)
        XCTAssertNil(multi.project(["pulse"]).oneDoubleOrNil())
    }
    
    func testCommonValue() {
        let empty = MakeRelation(
            ["id", "name", "friendly", "count"])
        
        let one = MakeRelation(
            ["id", "name", "friendly", "age"],
            [1,    "cat",  1,          5],
            [2,    "cat",  1,          5])
        
        let multi = MakeRelation(
            ["id", "name", "friendly", "age"],
            [1,    "cat",  1,          5],
            [2,    "dog",  0,          3])
        
        let asString = { (value: RelationValue) -> String? in
            return value.get()
        }
        
        let asInt = { (value: RelationValue) -> Int64? in
            return value.get()
        }
        
        XCTAssertEqual(empty.project(["name"]).commonValue(asString), CommonValue.none)
        XCTAssertEqual(one.project(["name"]).commonValue(asString), CommonValue.one("cat"))
        XCTAssertEqual(multi.project(["name"]).commonValue(asString), CommonValue.multi)
        
        XCTAssertEqual(empty.project(["age"]).commonValue(asInt), CommonValue.none)
        XCTAssertEqual(one.project(["age"]).commonValue(asInt), CommonValue.one(5))
        XCTAssertEqual(multi.project(["age"]).commonValue(asInt), CommonValue.multi)
    }
}
