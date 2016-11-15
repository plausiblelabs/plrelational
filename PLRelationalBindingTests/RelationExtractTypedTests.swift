//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import PLRelational
@testable import PLRelationalBinding

class RelationAsTypedValueTests: BindingTestCase {
    
    func testExtractAllValues() {
        let empty = MakeRelation(
            ["id", "name"])
        
        let r = MakeRelation(
            ["id", "name"],
            [1,    "cat"],
            [2,    "dog"],
            [3,    "fish"])
        
        let rvset = Set([RelationValue("cat"), RelationValue("dog"), RelationValue("fish")])
        
        XCTAssertEqual(empty.project(["name"]).extractAllRelationValues(), Set())
        XCTAssertEqual(r.project(["name"]).extractAllRelationValues(), rvset)
        
        XCTAssertEqual(
            r.project(["name"]).extractAllValuesForSingleAttribute{
                let s: String = $0.get()!
                if s.characters.count <= 3 {
                    return "\(s)s"
                } else {
                    return nil
                }
            },
            Set(["cats", "dogs"]))
    }
    
    func testExtractOneValue() {
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
        XCTAssertNil(empty.extractValueFromOneRow(transform))
        XCTAssertEqual(one.select(expr).extractValueFromOneRow(transform), "cat:5")
        XCTAssertNil(multi.extractValueFromOneRow(transform))
        
        XCTAssertEqual(empty.extractValueFromOneRow(transform, orDefault: "default"), "default")
        XCTAssertEqual(one.select(expr).extractValueFromOneRow(transform, orDefault: "default"), "cat:5")
        XCTAssertEqual(multi.extractValueFromOneRow(transform, orDefault: "default"), "default")
        
        XCTAssertNil(empty.project(["name"]).extractOneRelationValueOrNil())
        XCTAssertEqual(one.project(["name"]).extractOneRelationValueOrNil(), RelationValue("cat"))
        XCTAssertNil(multi.project(["name"]).extractOneRelationValueOrNil())
        
        XCTAssertEqual(empty.project(["name"]).extractOneString(), "")
        XCTAssertEqual(one.project(["name"]).extractOneString(), "cat")
        XCTAssertEqual(multi.project(["name"]).extractOneString(), "")
        
        XCTAssertNil(empty.project(["name"]).extractOneStringOrNil(), "")
        XCTAssertEqual(one.project(["name"]).extractOneStringOrNil(), "cat")
        XCTAssertNil(multi.project(["name"]).extractOneStringOrNil())
        
        XCTAssertEqual(empty.project(["friendly"]).extractOneBool(), false)
        XCTAssertEqual(one.project(["friendly"]).extractOneBool(), true)
        XCTAssertEqual(multi.project(["friendly"]).extractOneBool(), false)
        
        XCTAssertNil(empty.project(["friendly"]).extractOneBoolOrNil())
        XCTAssertEqual(one.project(["friendly"]).extractOneBoolOrNil(), true)
        XCTAssertNil(multi.project(["friendly"]).extractOneBoolOrNil())
        
        XCTAssertEqual(empty.project(["age"]).extractOneInteger(), 0)
        XCTAssertEqual(one.project(["age"]).extractOneInteger(), 5)
        XCTAssertEqual(multi.project(["age"]).extractOneInteger(), 0)
        
        XCTAssertNil(empty.project(["age"]).extractOneIntegerOrNil())
        XCTAssertEqual(one.project(["age"]).extractOneIntegerOrNil(), 5)
        XCTAssertNil(multi.project(["age"]).extractOneIntegerOrNil())
        
        XCTAssertEqual(empty.project(["pulse"]).extractOneDouble(), 0.0)
        XCTAssertEqual(one.project(["pulse"]).extractOneDouble(), 2.0)
        XCTAssertEqual(multi.project(["pulse"]).extractOneDouble(), 0.0)
        
        XCTAssertNil(empty.project(["pulse"]).extractOneDoubleOrNil())
        XCTAssertEqual(one.project(["pulse"]).extractOneDoubleOrNil(), 2.0)
        XCTAssertNil(multi.project(["pulse"]).extractOneDoubleOrNil())
    }
    
    func testExtractCommonValue() {
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
        
        XCTAssertEqual(empty.project(["name"]).extractCommonValue(asString), CommonValue.none)
        XCTAssertEqual(one.project(["name"]).extractCommonValue(asString), CommonValue.one("cat"))
        XCTAssertEqual(multi.project(["name"]).extractCommonValue(asString), CommonValue.multi)
        
        XCTAssertEqual(empty.project(["age"]).extractCommonValue(asInt), CommonValue.none)
        XCTAssertEqual(one.project(["age"]).extractCommonValue(asInt), CommonValue.one(5))
        XCTAssertEqual(multi.project(["age"]).extractCommonValue(asInt), CommonValue.multi)
    }
}
