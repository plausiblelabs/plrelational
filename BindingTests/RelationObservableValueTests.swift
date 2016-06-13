//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import libRelational
@testable import Binding

class RelationObservableValueTests: BindingTestCase {
    
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
    
    func testObservable() {
        let db = makeDB().db
        let sqlr = db.createRelation("animal", scheme: ["id", "name"]).ok!
        let r = ChangeLoggingRelation(baseRelation: sqlr)

        let observable = r.select(Attribute("id") *== 1).project(["name"]).observable{ $0.oneString }
        var changeObserved = false
        _ = observable.addChangeObserver({ _ in changeObserved = true })
        
        XCTAssertEqual(observable.value, "")
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        r.add(["id": 1, "name": "cat"])
        
        XCTAssertEqual(observable.value, "cat")
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        r.add(["id": 2, "name": "dog"])

        XCTAssertNotNil(observable.value)
        XCTAssertEqual(observable.value, "cat")
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        r.delete(true)
        
        XCTAssertEqual(observable.value, "")
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
    }
    
    func testMutableObservable() {
        let sqliteDB = makeDB().db
        let loggingDB = ChangeLoggingDatabase(sqliteDB)
        let db = TransactionalDatabase(loggingDB)
        
        XCTAssertNil(sqliteDB.createRelation("animal", scheme: ["id", "name"]).err)
        let r = db["animal"]

        func updateName(newValue: String) {
            db.transaction{
                r.update(Attribute("id") *== 1, newValues: ["name": RelationValue(newValue)])
            }
        }
        
        var snapshotCount = 0
        var updateCount = 0
        var commitCount = 0
        
        let config: RelationMutationConfig<String> = RelationMutationConfig(
            snapshot: {
                snapshotCount += 1
                return db.takeSnapshot()
            },
            update: { newValue in
                updateCount += 1
                updateName(newValue)
            },
            commit: { _, newValue in
                commitCount += 1
                updateName(newValue)
            }
        )
        
        let observable = r.select(Attribute("id") *== 1).project(["name"]).mutableObservable(config, relationToValue: { $0.oneString })
        var changeObserved = false
        _ = observable.addChangeObserver({ _ in changeObserved = true })

        XCTAssertEqual(observable.value, "")
        XCTAssertEqual(snapshotCount, 0)
        XCTAssertEqual(updateCount, 0)
        XCTAssertEqual(commitCount, 0)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        r.add(["id": 1, "name": "cat"])
        
        XCTAssertEqual(observable.value, "cat")
        XCTAssertEqual(snapshotCount, 0)
        XCTAssertEqual(updateCount, 0)
        XCTAssertEqual(commitCount, 0)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false

        observable.update("dog", ChangeMetadata(transient: true))

        XCTAssertEqual(observable.value, "dog")
        XCTAssertEqual(snapshotCount, 1)
        XCTAssertEqual(updateCount, 1)
        XCTAssertEqual(commitCount, 0)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false

        observable.update("dogg", ChangeMetadata(transient: true))
        
        XCTAssertEqual(observable.value, "dogg")
        XCTAssertEqual(snapshotCount, 1)
        XCTAssertEqual(updateCount, 2)
        XCTAssertEqual(commitCount, 0)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false

        observable.update("dogg", ChangeMetadata(transient: false))

        // Note: Even when the value to be committed is not actually changing from the
        // previous transient value, the value still needs to be committed to the
        // underlying database (although observers will not be notified, since from
        // their perspective the value is not changing)
        XCTAssertEqual(observable.value, "dogg")
        XCTAssertEqual(snapshotCount, 1)
        XCTAssertEqual(updateCount, 2)
        XCTAssertEqual(commitCount, 1)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        observable.update("ant", ChangeMetadata(transient: false))
        
        XCTAssertEqual(observable.value, "ant")
        XCTAssertEqual(snapshotCount, 2)
        XCTAssertEqual(updateCount, 2)
        XCTAssertEqual(commitCount, 2)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        r.delete(true)
        
        XCTAssertEqual(observable.value, "")
        XCTAssertEqual(snapshotCount, 2)
        XCTAssertEqual(updateCount, 2)
        XCTAssertEqual(commitCount, 2)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
    }
    
    func testEmpty() {
        let db = makeDB().db
        let sqlr = db.createRelation("animal", scheme: ["id", "name"]).ok!
        let r = ChangeLoggingRelation(baseRelation: sqlr)

        let observable = r.empty
        var changeObserved = false
        _ = observable.addChangeObserver({ _ in changeObserved = true })
        
        XCTAssertTrue(observable.value)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false

        r.add(["id": 1, "name": "cat"])
        
        XCTAssertFalse(observable.value)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false

        r.add(["id": 2, "name": "dog"])
        
        // Verify that observers are not notified when observable value has not actually changeObserved
        XCTAssertFalse(observable.value)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false

        r.delete(true)

        XCTAssertTrue(observable.value)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
    }
    
    func testNonEmpty() {
        let db = makeDB().db
        let sqlr = db.createRelation("animal", scheme: ["id", "name"]).ok!
        let r = ChangeLoggingRelation(baseRelation: sqlr)
        
        let observable = r.nonEmpty
        var changeObserved = false
        _ = observable.addChangeObserver({ _ in changeObserved = true })
        
        XCTAssertFalse(observable.value)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        r.add(["id": 1, "name": "cat"])
        
        XCTAssertTrue(observable.value)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        r.add(["id": 2, "name": "dog"])
        
        // Verify that observers are not notified when observable value has not actually changeObserved
        XCTAssertTrue(observable.value)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        r.delete(true)
        
        XCTAssertFalse(observable.value)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
    }
    
    func testWhenNotEmpty() {
        let db = makeDB().db
        let sqlr = db.createRelation("animal", scheme: ["id", "name"]).ok!
        let r = ChangeLoggingRelation(baseRelation: sqlr)

        var counter: Int = 0
        struct Thing {
            let id: Int
        }
        
        let observable = r.whenNonEmpty{ _ -> Thing in counter += 1; return Thing(id: counter) }
        var changeObserved = false
        _ = observable.addChangeObserver({ _ in changeObserved = true })
        
        XCTAssertNil(observable.value)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        r.add(["id": 1, "name": "cat"])
        
        XCTAssertNotNil(observable.value)
        XCTAssertEqual(observable.value!.id, 1)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        r.add(["id": 2, "name": "dog"])
        
        XCTAssertNotNil(observable.value)
        XCTAssertEqual(observable.value!.id, 1)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        r.delete(true)
        
        XCTAssertNil(observable.value)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        r.add(["id": 3, "name": "fish"])
        
        XCTAssertNotNil(observable.value)
        XCTAssertEqual(observable.value!.id, 2)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
    }
    
    func testStringWhenMulti() {
        let db = makeDB().db
        let sqlr = db.createRelation("animal", scheme: ["id", "name"]).ok!
        let r = ChangeLoggingRelation(baseRelation: sqlr)
        
        let observable = r.project(["name"]).stringWhenMulti("multi")
        var changeObserved = false
        _ = observable.addChangeObserver({ _ in changeObserved = true })
        
        XCTAssertEqual(observable.value, "")
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        r.add(["id": 1, "name": "cat"])
        
        // Verify that observers are not notified when observable value has not actually changeObserved
        XCTAssertEqual(observable.value, "")
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        r.add(["id": 2, "name": "dog"])
        
        XCTAssertEqual(observable.value, "multi")
        XCTAssertEqual(changeObserved, true)
        changeObserved = false

        // Verify that value is considered "multi" when there is a single non-NULL value and a
        // single NULL value
        r.update(Attribute("id") *== 2, newValues: ["name": .NULL])

        XCTAssertEqual(observable.value, "multi")
        XCTAssertEqual(changeObserved, false)
        changeObserved = false

        r.delete(true)
        
        XCTAssertEqual(observable.value, "")
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
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
