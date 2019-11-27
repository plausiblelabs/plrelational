//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import PLRelational
@testable import PLRelationalBinding

class RelationMutationTests: BindingTestCase {
    
    func testUpdateValue() {
        let db = makeDB().db
        let sqlr = db.createRelation("animal", scheme: ["id", "name", "friendly", "age"]).ok!
        let r = ChangeLoggingRelation(baseRelation: sqlr)
        
        _ = r.add(["id": 1, "name": "cat", "friendly": 1, "age": 5])
        _ = r.add(["id": 2, "name": "dog", "friendly": 0, "age": 3])
        
        let name = r.project(["name"])
        let a1name = r.select(Attribute("id") *== 1).project(["name"])
        
        _ = a1name.updateString("kat")
        AssertEqual(r, MakeRelation(
            ["id", "name", "friendly", "age"],
            [1,    "kat",  1,          5],
            [2,    "dog",  0,          3]))
        
        _ = name.updateString("ant")
        AssertEqual(r, MakeRelation(
            ["id", "name", "friendly", "age"],
            [1,    "ant",  1,          5],
            [2,    "ant",  0,          3]))
        
        let friendly = r.project(["friendly"])
        let a1friendly = r.select(Attribute("id") *== 1).project(["friendly"])
        
        _ = a1friendly.updateBoolean(false)
        AssertEqual(r, MakeRelation(
            ["id", "name", "friendly", "age"],
            [1,    "ant",  0,          5],
            [2,    "ant",  0,          3]))
        
        _ = friendly.updateBoolean(true)
        AssertEqual(r, MakeRelation(
            ["id", "name", "friendly", "age"],
            [1,    "ant",  1,          5],
            [2,    "ant",  1,          3]))
        
        let age = r.project(["age"])
        let a1age = r.select(Attribute("id") *== 1).project(["age"])
        
        _ = a1age.updateInteger(7)
        AssertEqual(r, MakeRelation(
            ["id", "name", "friendly", "age"],
            [1,    "ant",  1,          7],
            [2,    "ant",  1,          3]))
        
        _ = age.updateInteger(8)
        AssertEqual(r, MakeRelation(
            ["id", "name", "friendly", "age"],
            [1,    "ant",  1,          8],
            [2,    "ant",  1,          8]))
    }
    
    func testAsyncUpdateValue() {
        let sqliteDB = makeDB().db
        _ = sqliteDB.createRelation("animal", scheme: ["id", "name", "friendly", "age"]).ok!
        let db = TransactionalDatabase(sqliteDB)
        let r = db["animal"]
        
        _ = r.add(["id": 1, "name": "cat", "friendly": 1, "age": 5])
        _ = r.add(["id": 2, "name": "dog", "friendly": 0, "age": 3])

        let name = r.project(["name"])
        let a1name = r.select(Attribute("id") *== 1).project(["name"])
        
        awaitCompletion{ a1name.asyncUpdateString("kat") }
        AssertEqual(r, MakeRelation(
            ["id", "name", "friendly", "age"],
            [1,    "kat",  1,          5],
            [2,    "dog",  0,          3]))
        
        awaitCompletion{ name.asyncUpdateString("ant") }
        AssertEqual(r, MakeRelation(
            ["id", "name", "friendly", "age"],
            [1,    "ant",  1,          5],
            [2,    "ant",  0,          3]))

        let friendly = r.project(["friendly"])
        let a1friendly = r.select(Attribute("id") *== 1).project(["friendly"])

        awaitCompletion{ a1friendly.asyncUpdateBoolean(false) }
        AssertEqual(r, MakeRelation(
            ["id", "name", "friendly", "age"],
            [1,    "ant",  0,          5],
            [2,    "ant",  0,          3]))
        
        awaitCompletion{ friendly.asyncUpdateBoolean(true) }
        AssertEqual(r, MakeRelation(
            ["id", "name", "friendly", "age"],
            [1,    "ant",  1,          5],
            [2,    "ant",  1,          3]))

        let age = r.project(["age"])
        let a1age = r.select(Attribute("id") *== 1).project(["age"])

        awaitCompletion{ a1age.asyncUpdateInteger(7) }
        AssertEqual(r, MakeRelation(
            ["id", "name", "friendly", "age"],
            [1,    "ant",  1,          7],
            [2,    "ant",  1,          3]))
        
        awaitCompletion{ age.asyncUpdateInteger(8) }
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
    
    func testAsyncReplaceValues() {
        let sqliteDB = makeDB().db
        _ = sqliteDB.createRelation("animal", scheme: ["name"]).ok!
        let db = TransactionalDatabase(sqliteDB)
        let r = db["animal"]
        
        awaitCompletion{ r.asyncReplaceValues(["cat", "dog"]) }
        AssertEqual(r, MakeRelation(
            ["name"],
            ["cat"],
            ["dog"]))

        awaitCompletion{ r.asyncReplaceValues(["dog", "fish"]) }
        AssertEqual(r, MakeRelation(
            ["name"],
            ["dog"],
            ["fish"]))

        awaitCompletion{ r.asyncReplaceValues([]) }
        AssertEqual(r, MakeRelation(
            ["name"]))
    }
}
