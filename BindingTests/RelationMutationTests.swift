//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import libRelational
@testable import Binding

class RelationMutationTests: BindingTestCase {
    
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
