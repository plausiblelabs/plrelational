//
//  RelationValueBindingTests.swift
//  Relational
//
//  Created by Chris Campbell on 5/27/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import XCTest
import libRelational
@testable import SampleApp

class RelationValueBindingTests: AppTestCase {
    
    func testAllValues() {
        let empty = MakeRelation(
            ["id", "name"])
        
        let r = MakeRelation(
            ["id", "name"],
            [1,    "cat"],
            [2,    "dog"],
            [3,    "fish"])
        
        let rvset = Set([RelationValue("cat"), RelationValue("dog"), RelationValue("fish")])

        XCTAssertEqual(Set(empty.project(["name"]).allValues), Set())
        XCTAssertEqual(Set(r.project(["name"]).allValues), rvset)

        XCTAssertEqual(
            Set(r.project(["name"]).allValues{
                let s: String = $0.get()!
                if s.characters.count <= 3 {
                    return "\(s)s"
                } else {
                    return nil
                }
            }),
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
        
        XCTAssertNil(empty.project(["name"]).oneValue)
        XCTAssertEqual(one.project(["name"]).oneValue, RelationValue("cat"))
        XCTAssertNil(multi.project(["name"]).oneValue)

        XCTAssertEqual(empty.project(["name"]).oneString, "")
        XCTAssertEqual(one.project(["name"]).oneString, "cat")
        XCTAssertEqual(multi.project(["name"]).oneString, "")

        XCTAssertNil(empty.project(["friendly"]).oneBool)
        XCTAssertEqual(one.project(["friendly"]).oneBool, true)
        XCTAssertNil(multi.project(["friendly"]).oneBool)
        
        XCTAssertEqual(empty.project(["age"]).oneInteger, 0)
        XCTAssertEqual(one.project(["age"]).oneInteger, 5)
        XCTAssertEqual(multi.project(["age"]).oneInteger, 0)
    }
    
    func testBindAllValues() {
//        let db = makeDB().db
//        let r = db.createRelation("animal", scheme: ["id", "name"]).ok!
        // TODO
    }
    
    func testEmpty() {
        let db = makeDB().db
        let sqlr = db.createRelation("animal", scheme: ["id", "name"]).ok!
        let r = ChangeLoggingRelation(baseRelation: sqlr)

        let binding = r.empty
        var changed = false
        _ = binding.addChangeObserver({ _ in changed = true })
        
        XCTAssertTrue(binding.value)
        XCTAssertFalse(changed)
        changed = false

        r.add(["id": 1, "name": "cat"])
        
        XCTAssertFalse(binding.value)
        XCTAssertTrue(changed)
        changed = false

        r.add(["id": 2, "name": "dog"])
        
        XCTAssertFalse(binding.value)
        // TODO: ValueBinding should not notify if value is not changing
        //XCTAssertFalse(changed)
        changed = false

        r.delete(true)

        XCTAssertTrue(binding.value)
        XCTAssertTrue(changed)
        changed = false
    }
    
    func testNonEmpty() {
        let db = makeDB().db
        let sqlr = db.createRelation("animal", scheme: ["id", "name"]).ok!
        let r = ChangeLoggingRelation(baseRelation: sqlr)
        
        let binding = r.nonEmpty
        var changed = false
        _ = binding.addChangeObserver({ _ in changed = true })
        
        XCTAssertFalse(binding.value)
        XCTAssertFalse(changed)
        changed = false
        
        r.add(["id": 1, "name": "cat"])
        
        XCTAssertTrue(binding.value)
        XCTAssertTrue(changed)
        changed = false
        
        r.add(["id": 2, "name": "dog"])
        
        XCTAssertTrue(binding.value)
        // TODO: ValueBinding should not notify if value is not changing
        //XCTAssertFalse(changed)
        changed = false
        
        r.delete(true)
        
        XCTAssertFalse(binding.value)
        XCTAssertTrue(changed)
        changed = false
    }
    
    func testWhenNotEmpty() {
        let db = makeDB().db
        let sqlr = db.createRelation("animal", scheme: ["id", "name"]).ok!
        let r = ChangeLoggingRelation(baseRelation: sqlr)

        var counter: Int = 0
        struct Thing {
            let id: Int
        }
        
        let binding = r.whenNonEmpty{ _ -> Thing in counter += 1; return Thing(id: counter) }
        var changed = false
        _ = binding.addChangeObserver({ _ in changed = true })
        
        XCTAssertNil(binding.value)
        XCTAssertFalse(changed)
        changed = false
        
        r.add(["id": 1, "name": "cat"])
        
        XCTAssertNotNil(binding.value)
        XCTAssertEqual(binding.value!.id, 1)
        XCTAssertTrue(changed)
        changed = false
        
        r.add(["id": 2, "name": "dog"])
        
        XCTAssertNotNil(binding.value)
        XCTAssertEqual(binding.value!.id, 1)
        XCTAssertFalse(changed)
        changed = false
        
        r.delete(true)
        
        XCTAssertNil(binding.value)
        XCTAssertTrue(changed)
        changed = false
        
        r.add(["id": 3, "name": "fish"])
        
        XCTAssertNotNil(binding.value)
        XCTAssertEqual(binding.value!.id, 2)
        XCTAssertTrue(changed)
        changed = false
    }
    
    func testStringWhenMulti() {
        let db = makeDB().db
        let sqlr = db.createRelation("animal", scheme: ["id", "name"]).ok!
        let r = ChangeLoggingRelation(baseRelation: sqlr)
        
        let binding = r.project(["name"]).stringWhenMulti("multi")
        var changed = false
        _ = binding.addChangeObserver({ _ in changed = true })
        
        XCTAssertEqual(binding.value, "")
        XCTAssertFalse(changed)
        changed = false
        
        r.add(["id": 1, "name": "cat"])
        
        XCTAssertEqual(binding.value, "")
        // TODO: ValueBinding should not notify if value is not changing
        //XCTAssertFalse(changed)
        changed = false
        
        r.add(["id": 2, "name": "dog"])
        
        XCTAssertEqual(binding.value, "multi")
        XCTAssertTrue(changed)
        changed = false
        
        r.delete(true)
        
        XCTAssertEqual(binding.value, "")
        XCTAssertTrue(changed)
        changed = false
    }
    
    func testUpdateValue() {
        let db = makeDB().db
        let sqlr = db.createRelation("animal", scheme: ["id", "name", "friendly", "age"]).ok!
        let r = ChangeLoggingRelation(baseRelation: sqlr)
        
        r.add(["id": 1, "name": "cat", "friendly": 1, "age": 5])
        r.add(["id": 2, "name": "dog", "friendly": 0, "age": 3])

        let name = r.project(["name"])
        let a1name = r.select(Attribute("id") *== 1).project(["name"])
        
        a1name.updateString("kat")
        AssertEqual(r, MakeRelation(
            ["id", "name", "friendly", "age"],
            [1,    "kat",  1,          5],
            [2,    "dog",  0,          3]))
        
        name.updateString("ant")
        AssertEqual(r, MakeRelation(
            ["id", "name", "friendly", "age"],
            [1,    "ant",  1,          5],
            [2,    "ant",  0,          3]))
        
        let friendly = r.project(["friendly"])
        let a1friendly = r.select(Attribute("id") *== 1).project(["friendly"])
        
        a1friendly.updateBoolean(false)
        AssertEqual(r, MakeRelation(
            ["id", "name", "friendly", "age"],
            [1,    "ant",  0,          5],
            [2,    "ant",  0,          3]))
        
        friendly.updateBoolean(true)
        AssertEqual(r, MakeRelation(
            ["id", "name", "friendly", "age"],
            [1,    "ant",  1,          5],
            [2,    "ant",  1,          3]))
        
        let age = r.project(["age"])
        let a1age = r.select(Attribute("id") *== 1).project(["age"])
        
        a1age.updateInteger(7)
        AssertEqual(r, MakeRelation(
            ["id", "name", "friendly", "age"],
            [1,    "ant",  1,          7],
            [2,    "ant",  1,          3]))
        
        age.updateInteger(8)
        AssertEqual(r, MakeRelation(
            ["id", "name", "friendly", "age"],
            [1,    "ant",  1,          8],
            [2,    "ant",  1,          8]))
    }
    
    func testReplaceValues() {
        let db = makeDB().db
        let sqlr = db.createRelation("animal", scheme: ["name"]).ok!
        let r = ChangeLoggingRelation(baseRelation: sqlr)

        r.replaceValues(["cat", "dog"])
        AssertEqual(r, MakeRelation(
            ["name"],
            ["cat"],
            ["dog"]))
        
        r.replaceValues(["dog", "fish"])
        AssertEqual(r, MakeRelation(
            ["name"],
            ["dog"],
            ["fish"]))
        
        r.replaceValues([])
        AssertEqual(r, MakeRelation(
            ["name"]))
    }
}
