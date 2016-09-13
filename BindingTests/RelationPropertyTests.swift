//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import libRelational
@testable import Binding

class RelationPropertyTests: BindingTestCase {
    
    func testReadOnlyProperty() {
        let db = makeDB().db
        let sqlr = db.createRelation("animal", scheme: ["id", "name"]).ok!
        let r = ChangeLoggingRelation(baseRelation: sqlr)
        
        let property = r.select(Attribute("id") *== 1).project(["name"]).property{ $0.oneString }
        var changeObserved = false
        _ = property.signal.observe({ _ in changeObserved = true })
        
        XCTAssertEqual(property.value, "")
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        _ = r.add(["id": 1, "name": "cat"])
        
        XCTAssertEqual(property.value, "cat")
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        _ = r.add(["id": 2, "name": "dog"])
        
        XCTAssertNotNil(property.value)
        XCTAssertEqual(property.value, "cat")
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        _ = r.delete(true)
        
        XCTAssertEqual(property.value, "")
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
    }
    
    func testReadOnlyPropertyWithJoinAndDelete() {
        let sqliteDB = makeDB().db
        let db = TransactionalDatabase(sqliteDB)
        func createRelation(_ name: String, _ scheme: Scheme) -> MutableRelation {
            let createResult = sqliteDB.createRelation(name, scheme: scheme)
            precondition(createResult.ok != nil)
            return db[name]
        }
        
        var objects = createRelation("object", ["id", "name", "type"])
        var docItems = createRelation("doc_item", ["id"])
        var selectedDocItemID = createRelation("selected_doc_item", ["id"])
        
        let selectedDocItem = selectedDocItemID.join(objects).project(["id", "name"])

        struct DocItem {
            let id: Int64
            let name: String
        }
        
        let property = selectedDocItem.property{ relation in
            return relation.oneValueFromRow{ row in
                return DocItem(id: row["id"].get()!, name: row["name"].get()!)
            }
        }

        db.transaction{
            _ = objects.add(["id": 1, "name": "One", "type": 0])
            _ = docItems.add(["id": 1])
            _ = objects.add(["id": 2, "name": "Two", "type": 0])
            _ = docItems.add(["id": 2])
        }
        
        var changeObserved = false
        _ = property.signal.observe({ _ in changeObserved = true })

        XCTAssertEqual(property.value?.name, nil)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false

        db.transaction{
            _ = selectedDocItemID.add(["id": 1])
        }
        
        XCTAssertEqual(property.value?.name, "One")
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        db.transaction{
            _ = objects.delete(Attribute("id") *== 1)
            _ = docItems.delete(Attribute("id") *== 1)
        }

        XCTAssertEqual(property.value?.name, nil)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
    }
    
    func testEmpty() {
        let db = makeDB().db
        let sqlr = db.createRelation("animal", scheme: ["id", "name"]).ok!
        let r = ChangeLoggingRelation(baseRelation: sqlr)
        
        let property = r.empty
        var changeObserved = false
        _ = property.signal.observe({ _ in changeObserved = true })
        
        XCTAssertTrue(property.value)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        _ = r.add(["id": 1, "name": "cat"])
        
        XCTAssertFalse(property.value)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        _ = r.add(["id": 2, "name": "dog"])
        
        // Verify that observers are not notified when property value has not actually changed
        XCTAssertFalse(property.value)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        _ = r.delete(true)
        
        XCTAssertTrue(property.value)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
    }
    
    func testNonEmpty() {
        let db = makeDB().db
        let sqlr = db.createRelation("animal", scheme: ["id", "name"]).ok!
        let r = ChangeLoggingRelation(baseRelation: sqlr)
        
        let property = r.nonEmpty
        var changeObserved = false
        _ = property.signal.observe({ _ in changeObserved = true })
        
        XCTAssertFalse(property.value)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        _ = r.add(["id": 1, "name": "cat"])
        
        XCTAssertTrue(property.value)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        _ = r.add(["id": 2, "name": "dog"])
        
        // Verify that observers are not notified when property value has not actually changed
        XCTAssertTrue(property.value)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        _ = r.delete(true)
        
        XCTAssertFalse(property.value)
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
        
        let property = r.whenNonEmpty{ _ -> Thing in counter += 1; return Thing(id: counter) }
        var changeObserved = false
        _ = property.signal.observe({ _ in changeObserved = true })
        
        XCTAssertNil(property.value)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        _ = r.add(["id": 1, "name": "cat"])
        
        XCTAssertNotNil(property.value)
        XCTAssertEqual(property.value!.id, 1)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        _ = r.add(["id": 2, "name": "dog"])
        
        XCTAssertNotNil(property.value)
        XCTAssertEqual(property.value!.id, 1)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        _ = r.delete(true)
        
        XCTAssertNil(property.value)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        _ = r.add(["id": 3, "name": "fish"])
        
        XCTAssertNotNil(property.value)
        XCTAssertEqual(property.value!.id, 2)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
    }
    
    func testStringWhenMulti() {
        let db = makeDB().db
        let sqlr = db.createRelation("animal", scheme: ["id", "name"]).ok!
        let r = ChangeLoggingRelation(baseRelation: sqlr)
        
        let property = r.project(["name"]).stringWhenMulti("multi")
        var changeObserved = false
        _ = property.signal.observe({ _ in changeObserved = true })
        
        XCTAssertEqual(property.value, "")
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        _ = r.add(["id": 1, "name": "cat"])
        
        // Verify that observers are not notified when property value has not actually changed
        XCTAssertEqual(property.value, "")
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        _ = r.add(["id": 2, "name": "dog"])
        
        XCTAssertEqual(property.value, "multi")
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        // Verify that value is considered "multi" when there is a single non-NULL value and a
        // single NULL value
        _ = r.update(Attribute("id") *== 2, newValues: ["name": .null])
        
        XCTAssertEqual(property.value, "multi")
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        _ = r.delete(true)
        
        XCTAssertEqual(property.value, "")
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
    }
    
    func testReadWriteProperty() {
        let sqliteDB = makeDB().db
        let loggingDB = ChangeLoggingDatabase(sqliteDB)
        let db = TransactionalDatabase(loggingDB)

        XCTAssertNil(sqliteDB.createRelation("animal", scheme: ["id", "name"]).err)
        let r = db["animal"]

        func updateName(_ newValue: String) {
            db.transaction{
                _ = r.update(Attribute("id") *== 1, newValues: ["name": RelationValue(newValue)])
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

        let relationProperty = r.select(Attribute("id") *== 1).project(["name"]).property(config, relationToValue: { $0.oneString })
        var changeObserved = false
        _ = relationProperty.signal.observe({ _ in changeObserved = true })

        XCTAssertEqual(relationProperty.value, "")
        XCTAssertEqual(snapshotCount, 0)
        XCTAssertEqual(updateCount, 0)
        XCTAssertEqual(commitCount, 0)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false

        _ = r.add(["id": 1, "name": "cat"])

        XCTAssertEqual(relationProperty.value, "cat")
        XCTAssertEqual(snapshotCount, 0)
        XCTAssertEqual(updateCount, 0)
        XCTAssertEqual(commitCount, 0)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false

        // TODO: We use `valueChanging: { true }` here to simulate how TextField.string works
        // (since that one is an ExternalValueProperty) relative to the "Note" comment below.
        // Possibly a better way to deal with all this would be to actually notify observers
        // in the the case where the value is not changing but the transient flag *is* changing.
        let otherProperty = mutableValueProperty("", valueChanging: { _ in true })
        _ = otherProperty <~> relationProperty

        otherProperty.change("dog", transient: true)

        XCTAssertEqual(relationProperty.value, "dog")
        XCTAssertEqual(snapshotCount, 1)
        XCTAssertEqual(updateCount, 1)
        XCTAssertEqual(commitCount, 0)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false

        otherProperty.change("dogg", transient: true)

        XCTAssertEqual(relationProperty.value, "dogg")
        XCTAssertEqual(snapshotCount, 1)
        XCTAssertEqual(updateCount, 2)
        XCTAssertEqual(commitCount, 0)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false

        otherProperty.change("dogg", transient: false)

        // Note: Even when the value to be committed is not actually changing from the
        // previous transient value, the value still needs to be committed to the
        // underlying database (although observers will not be notified, since from
        // their perspective the value is not changing)
        // TODO: This only works because of the `valueChanging` hack for `otherProperty`, see TODO above.
        XCTAssertEqual(relationProperty.value, "dogg")
        XCTAssertEqual(snapshotCount, 1)
        XCTAssertEqual(updateCount, 2)
        XCTAssertEqual(commitCount, 1)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false

        otherProperty.change("ant", transient: false)

        XCTAssertEqual(relationProperty.value, "ant")
        XCTAssertEqual(snapshotCount, 2)
        XCTAssertEqual(updateCount, 2)
        XCTAssertEqual(commitCount, 2)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        _ = r.delete(true)
        
        XCTAssertEqual(relationProperty.value, "")
        XCTAssertEqual(snapshotCount, 2)
        XCTAssertEqual(updateCount, 2)
        XCTAssertEqual(commitCount, 2)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
    }
}
