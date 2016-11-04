//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import PLRelational
@testable import PLRelationalBinding

class RelationArrayPropertyTests: BindingTestCase {
    
    private typealias Pos = ArrayPos<RowArrayElement>
    private typealias Change = ArrayChange<RowArrayElement>
    
    func testInitWithExplicitOrder() {
        let sqliteDB = makeDB().db
        let sqliteRelation = sqliteDB.createRelation("page", scheme: ["id", "name", "order"]).ok!
        let db = TransactionalDatabase(sqliteDB)
        let r = db["page"]

        // Add some existing data to the underlying SQLite database
        func addPage(_ pageID: Int64, name: String, order: Double) {
            _ = sqliteRelation.add([
                "id": RelationValue(pageID),
                "name": RelationValue(name),
                "order": RelationValue(order)
            ])
        }
        addPage(1, name: "Page1", order: 1.0)
        addPage(3, name: "Page3", order: 3.0)
        addPage(2, name: "Page2", order: 2.0)
        addPage(4, name: "Page4", order: 4.0)
        
        let runloop = CFRunLoopGetCurrent()
        
        func awaitCompletion(_ f: () -> Void) {
            f()
            CFRunLoopRun()
        }
        
        var willChangeCount = 0
        var didChangeCount = 0
        var changes: [Change] = []

        let property = r.arrayProperty(idAttr: "id", orderAttr: "order")
        let removal = property.signal.observe(SignalObserver(
            valueWillChange: {
                willChangeCount += 1
            },
            valueChanging: { arrayChanges, _ in
                changes.append(contentsOf: arrayChanges)
            },
            valueDidChange: {
                didChangeCount += 1
                CFRunLoopStop(runloop)
            }
        ))
        
        // Verify that property value remains empty until we actually start it
        XCTAssertEqual(property.elements, [])
        XCTAssertEqual(willChangeCount, 0)
        XCTAssertEqual(didChangeCount, 0)
        XCTAssertEqual(changes, [])

        // Verify that in-memory array structure was built correctly after property/signal was started
        awaitCompletion{ property.start() }
        verifyArray(property, [
            "Page1",
            "Page2",
            "Page3",
            "Page4"
        ])
        XCTAssertEqual(willChangeCount, 1)
        XCTAssertEqual(didChangeCount, 1)
        // TODO
        //XCTAssertEqual(changes, [])

        removal()
    }
    
    func testInsertMoveDeleteWithExplicitOrder() {
        let sqliteDB = makeDB().db
        let sqliteRelation = sqliteDB.createRelation("page", scheme: ["id", "name", "order"]).ok!
        let loggingDB = ChangeLoggingDatabase(sqliteDB)
        let db = TransactionalDatabase(loggingDB)
        let r = db["page"]
        
        let runloop = CFRunLoopGetCurrent()
        
        func awaitCompletion(_ f: () -> Void) {
            f()
            CFRunLoopRun()
        }
        
        var willChangeCount = 0
        var didChangeCount = 0
        var changes: [Change] = []
        
        let property = r.arrayProperty(idAttr: "id", orderAttr: "order")
        let removal = property.signal.observe(SignalObserver(
            valueWillChange: {
                willChangeCount += 1
            },
            valueChanging: { arrayChanges, _ in
                changes.append(contentsOf: arrayChanges)
            },
            valueDidChange: {
                didChangeCount += 1
                CFRunLoopStop(runloop)
            }
        ))
        
        func addPage(_ pageID: Int64, name: String, previousID: Int64?) {
            let previous = previousID.map{RelationValue($0)}
            let pos = Pos(previousID: previous, nextID: nil)
            let order = property.orderForPos(pos)
            let row: Row = [
                "id": RelationValue(pageID),
                "name": RelationValue(name),
                "order": RelationValue(order)
            ]
            awaitCompletion{
                r.asyncAdd(row)
            }
        }
        
        func deletePage(_ pageID: Int64) {
            awaitCompletion{
                r.asyncDelete(Attribute("id") *== RelationValue(pageID))
            }
        }

        func renamePage(_ pageID: Int64, _ name: String) {
            awaitCompletion{
                r.asyncUpdate(Attribute("id") *== RelationValue(pageID), newValues: ["name": RelationValue(name)])
            }
        }
        
        func movePage(srcIndex: Int, dstIndex: Int) {
            let elem = property.elements[srcIndex]
            let order = property.orderForMove(srcIndex: srcIndex, dstIndex: dstIndex)
            awaitCompletion{
                r.asyncUpdate(Attribute("id") *== elem.id, newValues: ["order": RelationValue(order)])
            }
        }

        func verifyChanges(_ expected: [Change], file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(changes, expected, file: file, line: line)
            changes = []
        }

        func verifySQLite(_ expected: Relation, file: StaticString = #file, line: UInt = #line) {
            XCTAssertNil(loggingDB.save().err)
            AssertEqual(sqliteDB["page"]!, expected, file: file, line: line)
        }

        // Verify that property value remains empty until we actually start it
        XCTAssertEqual(property.elements, [])
        XCTAssertEqual(willChangeCount, 0)
        XCTAssertEqual(didChangeCount, 0)
        XCTAssertEqual(changes, [])

        // Verify that in-memory array structure is empty after property/signal was started
        awaitCompletion{ property.start() }
        XCTAssertEqual(willChangeCount, 1)
        XCTAssertEqual(didChangeCount, 1)
        verifyArray(property, [])
        verifyChanges([.initial([])])
        
        // Insert some pages
        addPage(1, name: "Page1", previousID: nil)
        addPage(2, name: "Page2", previousID: 1)
        addPage(3, name: "Page3", previousID: 2)
        addPage(4, name: "Page4", previousID: 3)
        XCTAssertEqual(willChangeCount, 5)
        XCTAssertEqual(didChangeCount, 5)
        verifyArray(property, [
            "Page1",
            "Page2",
            "Page3",
            "Page4"
        ])
        verifyChanges([
            .insert(0),
            .insert(1),
            .insert(2),
            .insert(3),
        ])
        verifySQLite(MakeRelation(
            ["id", "name",  "order"],
            [1,    "Page1", 5.0],
            [2,    "Page2", 7.0],
            [3,    "Page3", 8.0],
            [4,    "Page4", 8.5]
        ))
        
        // Update a page name; verify that an `update` change is sent and the element's row data
        // is updated as well
        renamePage(3, "PageX")
        XCTAssertEqual(willChangeCount, 6)
        XCTAssertEqual(didChangeCount, 6)
        verifyArray(property, [
            "Page1",
            "Page2",
            "PageX",
            "Page4"
        ])
        verifyChanges([
            .update(2)
        ])
        verifySQLite(MakeRelation(
            ["id", "name",  "order"],
            [1,    "Page1", 5.0],
            [2,    "Page2", 7.0],
            [3,    "PageX", 8.0],
            [4,    "Page4", 8.5]
        ))

        // Re-order a page
        movePage(srcIndex: 2, dstIndex: 0)
        XCTAssertEqual(willChangeCount, 7)
        XCTAssertEqual(didChangeCount, 7)
        verifyArray(property, [
            "PageX",
            "Page1",
            "Page2",
            "Page4"
        ])
        verifyChanges([
            .move(srcIndex: 2, dstIndex: 0)
        ])
        verifySQLite(MakeRelation(
            ["id", "name",  "order"],
            [1,    "Page1", 5.0],
            [2,    "Page2", 7.0],
            [3,    "PageX", 3.0],
            [4,    "Page4", 8.5]
        ))

        // Delete a page
        deletePage(1)
        XCTAssertEqual(willChangeCount, 8)
        XCTAssertEqual(didChangeCount, 8)
        verifyArray(property, [
            "PageX",
            "Page2",
            "Page4"
        ])
        verifyChanges([
            .delete(1)
        ])
        verifySQLite(MakeRelation(
            ["id", "name",  "order"],
            [2,    "Page2", 7.0],
            [3,    "PageX", 3.0],
            [4,    "Page4", 8.5]
        ))
        
        removal()
    }
    
    func testInitSortedByName() {
        let sqliteDB = makeDB().db
        let sqliteRelation = sqliteDB.createRelation("person", scheme: ["id", "name"]).ok!
        let db = TransactionalDatabase(sqliteDB)
        let r = db["person"]
        
        // Add some existing data to the underlying SQLite database
        func addPerson(_ personID: Int64, _ name: String) {
            _ = sqliteRelation.add([
                "id": RelationValue(personID),
                "name": RelationValue(name)
            ])
        }
        addPerson(1, "Alice")
        addPerson(2, "Donald")
        addPerson(3, "Carlos")
        addPerson(4, "Bob")
        
        let runloop = CFRunLoopGetCurrent()
        
        func awaitCompletion(_ f: () -> Void) {
            f()
            CFRunLoopRun()
        }
        
        var willChangeCount = 0
        var didChangeCount = 0
        var changes: [Change] = []
        
        let property = r.arrayProperty(idAttr: "id", orderAttr: "name")
        let removal = property.signal.observe(SignalObserver(
            valueWillChange: {
                willChangeCount += 1
            },
            valueChanging: { arrayChanges, _ in
                changes.append(contentsOf: arrayChanges)
            },
            valueDidChange: {
                didChangeCount += 1
                CFRunLoopStop(runloop)
            }
        ))
        
        // Verify that property value remains empty until we actually start it
        XCTAssertEqual(property.elements, [])
        XCTAssertEqual(willChangeCount, 0)
        XCTAssertEqual(didChangeCount, 0)
        XCTAssertEqual(changes, [])
        
        // Verify that in-memory array structure was built correctly after property/signal was started
        awaitCompletion{ property.start() }
        verifyArray(property, [
            "Alice",
            "Bob",
            "Carlos",
            "Donald"
        ])
        XCTAssertEqual(willChangeCount, 1)
        XCTAssertEqual(didChangeCount, 1)
        // TODO
        //XCTAssertEqual(changes, [])
        
        removal()
    }
    
    func testInsertRenameDeleteSortedByName() {
        let sqliteDB = makeDB().db
        let sqliteRelation = sqliteDB.createRelation("person", scheme: ["id", "name"]).ok!
        let loggingDB = ChangeLoggingDatabase(sqliteDB)
        let db = TransactionalDatabase(loggingDB)
        let r = db["person"]
        
        let runloop = CFRunLoopGetCurrent()
        
        func awaitCompletion(_ f: () -> Void) {
            f()
            CFRunLoopRun()
        }
        
        var willChangeCount = 0
        var didChangeCount = 0
        var changes: [Change] = []
        
        let property = r.arrayProperty(idAttr: "id", orderAttr: "name")
        let removal = property.signal.observe(SignalObserver(
            valueWillChange: {
                willChangeCount += 1
            },
            valueChanging: { arrayChanges, _ in
                changes.append(contentsOf: arrayChanges)
            },
            valueDidChange: {
                didChangeCount += 1
                CFRunLoopStop(runloop)
            }
        ))
        
        func addPerson(_ personID: Int64, _ name: String) {
            let row: Row = [
                "id": RelationValue(personID),
                "name": RelationValue(name)
            ]
            awaitCompletion{
                r.asyncAdd(row)
            }
        }
        
        func deletePerson(_ personID: Int64) {
            awaitCompletion{
                r.asyncDelete(Attribute("id") *== RelationValue(personID))
            }
        }
        
        func renamePerson(_ personID: Int64, _ name: String) {
            awaitCompletion{
                r.asyncUpdate(Attribute("id") *== RelationValue(personID), newValues: ["name": RelationValue(name)])
            }
        }
        
        func verifyChanges(_ expected: [Change], file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(changes, expected, file: file, line: line)
            changes = []
        }
        
        func verifySQLite(_ expected: Relation, file: StaticString = #file, line: UInt = #line) {
            XCTAssertNil(loggingDB.save().err)
            AssertEqual(sqliteDB["person"]!, expected, file: file, line: line)
        }
        
        // Verify that property value remains empty until we actually start it
        XCTAssertEqual(property.elements, [])
        XCTAssertEqual(willChangeCount, 0)
        XCTAssertEqual(didChangeCount, 0)
        XCTAssertEqual(changes, [])
        
        // Verify that in-memory array structure is empty after property/signal was started
        awaitCompletion{ property.start() }
        XCTAssertEqual(willChangeCount, 1)
        XCTAssertEqual(didChangeCount, 1)
        verifyArray(property, [])
        verifyChanges([.initial([])])
        
        // Insert some persons
        addPerson(1, "Alice")
        addPerson(2, "Donald")
        addPerson(3, "Carlos")
        addPerson(4, "Bob")
        XCTAssertEqual(willChangeCount, 5)
        XCTAssertEqual(didChangeCount, 5)
        verifyArray(property, [
            "Alice",
            "Bob",
            "Carlos",
            "Donald"
        ])
        verifyChanges([
            .insert(0),
            .insert(1),
            .insert(1),
            .insert(1),
        ])
        verifySQLite(MakeRelation(
            ["id", "name"],
            [1,    "Alice"],
            [2,    "Donald"],
            [3,    "Carlos"],
            [4,    "Bob"]
        ))
        
        // Rename a person
        renamePerson(2, "Bon")
        XCTAssertEqual(willChangeCount, 6)
        XCTAssertEqual(didChangeCount, 6)
        verifyArray(property, [
            "Alice",
            "Bob",
            "Bon",
            "Carlos"
        ])
        verifyChanges([
            .move(srcIndex: 3, dstIndex: 2)
        ])
        verifySQLite(MakeRelation(
            ["id", "name"],
            [1,    "Alice"],
            [2,    "Bon"],
            [3,    "Carlos"],
            [4,    "Bob"]
        ))

        // Delete a person
        deletePerson(1)
        XCTAssertEqual(willChangeCount, 7)
        XCTAssertEqual(didChangeCount, 7)
        verifyArray(property, [
            "Bob",
            "Bon",
            "Carlos"
        ])
        verifyChanges([
            .delete(0)
        ])
        verifySQLite(MakeRelation(
            ["id", "name"],
            [2,    "Bon"],
            [3,    "Carlos"],
            [4,    "Bob"]
        ))
        
        removal()
    }
}
