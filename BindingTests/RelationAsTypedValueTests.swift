//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import libRelational
@testable import Binding

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
        
        XCTAssertEqual(empty.project(["name"]).allValues, Set())
        XCTAssertEqual(r.project(["name"]).allValues, rvset)
        
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
        
        XCTAssertNil(empty.project(["name"]).anyValue)
        XCTAssertTrue(rvset.contains(r.project(["name"]).anyValue!))
        XCTAssertTrue(strset.contains(r.project(["name"]).anyValue{ v -> String? in v.get()! }!))
    }
    
    func testOneValue() {
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
        
        let expr: SelectExpression = Attribute("id") *== 1
        let transform = { (row: Row) -> String? in "\(row["name"]):\(row["age"])" }
        XCTAssertNil(empty.oneValueFromRow(transform))
        XCTAssertEqual(one.select(expr).oneValueFromRow(transform), "cat:5")
        XCTAssertNil(multi.oneValueFromRow(transform))
        
        XCTAssertEqual(empty.oneValueFromRow(transform, orDefault: "default"), "default")
        XCTAssertEqual(one.select(expr).oneValueFromRow(transform, orDefault: "default"), "cat:5")
        XCTAssertEqual(multi.oneValueFromRow(transform, orDefault: "default"), "default")
        
        XCTAssertNil(empty.project(["name"]).oneValue)
        XCTAssertEqual(one.project(["name"]).oneValue, RelationValue("cat"))
        XCTAssertNil(multi.project(["name"]).oneValue)
        
        XCTAssertEqual(empty.project(["name"]).oneString, "")
        XCTAssertEqual(one.project(["name"]).oneString, "cat")
        XCTAssertEqual(multi.project(["name"]).oneString, "")
        
        XCTAssertNil(empty.project(["name"]).oneStringOrNil, "")
        XCTAssertEqual(one.project(["name"]).oneStringOrNil, "cat")
        XCTAssertNil(multi.project(["name"]).oneStringOrNil)
        
        XCTAssertEqual(empty.project(["friendly"]).oneBool, false)
        XCTAssertEqual(one.project(["friendly"]).oneBool, true)
        XCTAssertEqual(multi.project(["friendly"]).oneBool, false)
        
        XCTAssertNil(empty.project(["friendly"]).oneBoolOrNil)
        XCTAssertEqual(one.project(["friendly"]).oneBoolOrNil, true)
        XCTAssertNil(multi.project(["friendly"]).oneBoolOrNil)
        
        XCTAssertEqual(empty.project(["age"]).oneInteger, 0)
        XCTAssertEqual(one.project(["age"]).oneInteger, 5)
        XCTAssertEqual(multi.project(["age"]).oneInteger, 0)
        
        XCTAssertNil(empty.project(["age"]).oneIntegerOrNil)
        XCTAssertEqual(one.project(["age"]).oneIntegerOrNil, 5)
        XCTAssertNil(multi.project(["age"]).oneIntegerOrNil)
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
        
        XCTAssertEqual(empty.project(["name"]).commonValue(asString), CommonValue.None)
        XCTAssertEqual(one.project(["name"]).commonValue(asString), CommonValue.One("cat"))
        XCTAssertEqual(multi.project(["name"]).commonValue(asString), CommonValue.Multi)
        
        XCTAssertEqual(empty.project(["age"]).commonValue(asInt), CommonValue.None)
        XCTAssertEqual(one.project(["age"]).commonValue(asInt), CommonValue.One(5))
        XCTAssertEqual(multi.project(["age"]).commonValue(asInt), CommonValue.Multi)
    }
}
