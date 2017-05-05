//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import PLRelational
@testable import PLRelationalBinding

private typealias Pos = ArrayPos<RowArrayElement>
private typealias Change = ArrayChange<RowArrayElement>

private class TestArrayObserver {
    var willChangeCount = 0
    var didChangeCount = 0
    var changes: [Change] = []
    
    func observe(_ property: ArrayProperty<RowArrayElement>) -> ObserverRemoval {
        return property.signal.observe(SignalObserver(
            valueWillChange: {
                self.willChangeCount += 1
            },
            valueChanging: { arrayChanges, _ in
                self.changes.append(contentsOf: arrayChanges)
            },
            valueDidChange: {
                self.didChangeCount += 1
            }
        ))
    }
    
    func reset() {
        willChangeCount = 0
        didChangeCount = 0
        changes = []
    }
}

class RelationArrayPropertyTests: BindingTestCase {
    
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
        
        let property = r.arrayProperty(idAttr: "id", orderAttr: "order")
        let observer = TestArrayObserver()
        
        func verify(elements: [String], changes: [Change], willChangeCount: Int, didChangeCount: Int, file: StaticString = #file, line: UInt = #line) {
            verifyArray(property, elements, file: file, line: line)
            XCTAssertEqual(observer.changes, changes, file: file, line: line)
            XCTAssertEqual(observer.willChangeCount, willChangeCount, file: file, line: line)
            XCTAssertEqual(observer.didChangeCount, didChangeCount, file: file, line: line)
            observer.changes = []
        }
        
        // Verify that property value remains empty until we actually start it
        verify(elements: [], changes: [], willChangeCount: 0, didChangeCount: 0)
        
        // Verify that in-memory array structure is built correctly after signal is observed/started
        let removal = observer.observe(property)
        verify(elements: [], changes: [], willChangeCount: 1, didChangeCount: 0)
        awaitIdle()
        verify(
            elements: [
                "Page1",
                "Page2",
                "Page3",
                "Page4"
            ],
            changes: [.initial(property.elements)],
            willChangeCount: 1,
            didChangeCount: 1
        )

        removal()
    }
    
    func testInsertMoveDeleteWithExplicitOrder() {
        let sqliteDB = makeDB().db
        let sqliteRelation = sqliteDB.createRelation("page", scheme: ["id", "name", "order"]).ok!
        let loggingDB = ChangeLoggingDatabase(sqliteDB)
        let db = TransactionalDatabase(loggingDB)
        let r = db["page"]
        
        let property = r.arrayProperty(idAttr: "id", orderAttr: "order")
        let observer = TestArrayObserver()
        
        func addPage(_ pageID: Int64, name: String, previousID: Int64?) {
            let previous = previousID.map{RelationValue($0)}
            let pos = Pos(previousID: previous, nextID: nil)
            let order = property.orderForPos(pos)
            let row: Row = [
                "id": RelationValue(pageID),
                "name": RelationValue(name),
                "order": RelationValue(order)
            ]
            r.asyncAdd(row)
        }
        
        func deletePage(_ pageID: Int64) {
            r.asyncDelete(Attribute("id") *== RelationValue(pageID))
        }

        func renamePage(_ pageID: Int64, _ name: String) {
            r.asyncUpdate(Attribute("id") *== RelationValue(pageID), newValues: ["name": RelationValue(name)])
        }
        
        func movePage(srcIndex: Int, dstIndex: Int) {
            let elem = property.elements[srcIndex]
            let order = property.orderForMove(srcIndex: srcIndex, dstIndex: dstIndex)
            r.asyncUpdate(Attribute("id") *== elem.id, newValues: ["order": RelationValue(order)])
        }

        func verifySQLite(_ expected: Relation, file: StaticString = #file, line: UInt = #line) {
            XCTAssertNil(loggingDB.save().err)
            AssertEqual(sqliteDB["page"]!, expected, file: file, line: line)
        }
        
        func verify(elements: [String], changes: [Change], willChangeCount: Int, didChangeCount: Int, file: StaticString = #file, line: UInt = #line) {
            verifyArray(property, elements, file: file, line: line)
            XCTAssertEqual(observer.changes, changes, file: file, line: line)
            XCTAssertEqual(observer.willChangeCount, willChangeCount, file: file, line: line)
            XCTAssertEqual(observer.didChangeCount, didChangeCount, file: file, line: line)
            observer.changes = []
        }

        // Verify that property value remains empty until we actually start it
        verify(elements: [], changes: [], willChangeCount: 0, didChangeCount: 0)
        
        // Verify that in-memory array structure is built correctly after signal is observed/started
        let removal = observer.observe(property)
        verify(elements: [], changes: [], willChangeCount: 1, didChangeCount: 0)
        awaitIdle()
        verify(elements: [], changes: [.initial([])], willChangeCount: 1, didChangeCount: 1)

        // Insert some pages
        addPage(1, name: "Page1", previousID: nil)
        verify(elements: [], changes: [], willChangeCount: 2, didChangeCount: 1)
        // XXX: orderForPos relies on the current in-memory tree structure, so we await
        // async completion after each add
        awaitIdle()
        verify(elements: ["Page1"], changes: [.insert(0)], willChangeCount: 2, didChangeCount: 2)
        
        addPage(2, name: "Page2", previousID: 1)
        verify(elements: ["Page1"], changes: [], willChangeCount: 3, didChangeCount: 2)
        awaitIdle()
        verify(elements: ["Page1", "Page2"], changes: [.insert(1)], willChangeCount: 3, didChangeCount: 3)

        addPage(3, name: "Page3", previousID: 2)
        verify(elements: ["Page1", "Page2"], changes: [], willChangeCount: 4, didChangeCount: 3)
        awaitIdle()
        verify(elements: ["Page1", "Page2", "Page3"], changes: [.insert(2)], willChangeCount: 4, didChangeCount: 4)

        addPage(4, name: "Page4", previousID: 3)
        verify(elements: ["Page1", "Page2", "Page3"], changes: [], willChangeCount: 5, didChangeCount: 4)
        awaitIdle()
        verify(elements: ["Page1", "Page2", "Page3", "Page4"], changes: [.insert(3)], willChangeCount: 5, didChangeCount: 5)

        verifySQLite(MakeRelation(
            ["id", "name",  "order"],
            [1,    "Page1", 5.0],
            [2,    "Page2", 7.0],
            [3,    "Page3", 8.0],
            [4,    "Page4", 8.5]
        ))
        
        // Update a page name; verify that an `update` change is sent and the element's row data
        // is updated as well
        observer.reset()
        renamePage(3, "PageX")
        verify(elements: ["Page1", "Page2", "Page3", "Page4"], changes: [], willChangeCount: 1, didChangeCount: 0)
        awaitIdle()
        verify(elements: ["Page1", "Page2", "PageX", "Page4"], changes: [.update(2)], willChangeCount: 1, didChangeCount: 1)
        
        verifySQLite(MakeRelation(
            ["id", "name",  "order"],
            [1,    "Page1", 5.0],
            [2,    "Page2", 7.0],
            [3,    "PageX", 8.0],
            [4,    "Page4", 8.5]
        ))

        // Re-order a page
        observer.reset()
        movePage(srcIndex: 2, dstIndex: 0)
        verify(elements: ["Page1", "Page2", "PageX", "Page4"], changes: [], willChangeCount: 1, didChangeCount: 0)
        awaitIdle()
        verify(elements: ["PageX", "Page1", "Page2", "Page4"], changes: [.move(srcIndex: 2, dstIndex: 0)], willChangeCount: 1, didChangeCount: 1)
        
        verifySQLite(MakeRelation(
            ["id", "name",  "order"],
            [1,    "Page1", 5.0],
            [2,    "Page2", 7.0],
            [3,    "PageX", 3.0],
            [4,    "Page4", 8.5]
        ))

        // Delete a page
        observer.reset()
        deletePage(1)
        verify(elements: ["PageX", "Page1", "Page2", "Page4"], changes: [], willChangeCount: 1, didChangeCount: 0)
        awaitIdle()
        verify(elements: ["PageX", "Page2", "Page4"], changes: [.delete(1)], willChangeCount: 1, didChangeCount: 1)
        
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
        
        let property = r.arrayProperty(idAttr: "id", orderAttr: "name")
        let observer = TestArrayObserver()
        
        func verify(elements: [String], changes: [Change], willChangeCount: Int, didChangeCount: Int, file: StaticString = #file, line: UInt = #line) {
            verifyArray(property, elements, file: file, line: line)
            XCTAssertEqual(observer.changes, changes, file: file, line: line)
            XCTAssertEqual(observer.willChangeCount, willChangeCount, file: file, line: line)
            XCTAssertEqual(observer.didChangeCount, didChangeCount, file: file, line: line)
            observer.changes = []
        }

        // Verify that property value remains empty until we actually start it
        verify(elements: [], changes: [], willChangeCount: 0, didChangeCount: 0)
        
        // Verify that in-memory array structure was built correctly after property/signal was started
        let removal = observer.observe(property)
        verify(elements: [], changes: [], willChangeCount: 1, didChangeCount: 0)
        awaitIdle()
        verify(
            elements: [
                "Alice",
                "Bob",
                "Carlos",
                "Donald"
            ],
            changes: [.initial(property.elements)],
            willChangeCount: 1,
            didChangeCount: 1
        )

        removal()
    }
    
    func testInsertRenameDeleteSortedByName() {
        let sqliteDB = makeDB().db
        let sqliteRelation = sqliteDB.createRelation("person", scheme: ["id", "name"]).ok!
        let loggingDB = ChangeLoggingDatabase(sqliteDB)
        let db = TransactionalDatabase(loggingDB)
        let r = db["person"]
        
        let property = r.arrayProperty(idAttr: "id", orderAttr: "name")
        let observer = TestArrayObserver()
        
        func addPerson(_ personID: Int64, _ name: String) {
            let row: Row = [
                "id": RelationValue(personID),
                "name": RelationValue(name)
            ]
            r.asyncAdd(row)
        }
        
        func deletePerson(_ personID: Int64) {
            r.asyncDelete(Attribute("id") *== RelationValue(personID))
        }
        
        func renamePerson(_ personID: Int64, _ name: String) {
            r.asyncUpdate(Attribute("id") *== RelationValue(personID), newValues: ["name": RelationValue(name)])
        }
        
        func verify(elements: [String], changes: [Change], willChangeCount: Int, didChangeCount: Int, file: StaticString = #file, line: UInt = #line) {
            verifyArray(property, elements, file: file, line: line)
            XCTAssertEqual(observer.changes, changes, file: file, line: line)
            XCTAssertEqual(observer.willChangeCount, willChangeCount, file: file, line: line)
            XCTAssertEqual(observer.didChangeCount, didChangeCount, file: file, line: line)
            observer.changes = []
        }
        
        func verifySQLite(_ expected: Relation, file: StaticString = #file, line: UInt = #line) {
            XCTAssertNil(loggingDB.save().err)
            AssertEqual(sqliteDB["person"]!, expected, file: file, line: line)
        }
        
        // Verify that property value remains empty until we actually start it
        verify(elements: [], changes: [], willChangeCount: 0, didChangeCount: 0)
        
        // Verify that in-memory array structure is empty after signal is observed/started
        let removal = observer.observe(property)
        verify(elements: [], changes: [], willChangeCount: 1, didChangeCount: 0)
        awaitIdle()
        verify(elements: [], changes: [.initial([])], willChangeCount: 1, didChangeCount: 1)
        observer.reset()
        
        // Insert some persons
        addPerson(1, "Alice")
        verify(elements: [], changes: [], willChangeCount: 1, didChangeCount: 0)
        awaitIdle()
        verify(elements: ["Alice"], changes: [.insert(0)], willChangeCount: 1, didChangeCount: 1)
        observer.reset()

        addPerson(2, "Donald")
        verify(elements: ["Alice"], changes: [], willChangeCount: 1, didChangeCount: 0)
        awaitIdle()
        verify(elements: ["Alice", "Donald"], changes: [.insert(1)], willChangeCount: 1, didChangeCount: 1)
        observer.reset()

        addPerson(3, "Carlos")
        verify(elements: ["Alice", "Donald"], changes: [], willChangeCount: 1, didChangeCount: 0)
        awaitIdle()
        verify(elements: ["Alice", "Carlos", "Donald"], changes: [.insert(1)], willChangeCount: 1, didChangeCount: 1)
        observer.reset()

        addPerson(4, "Bob")
        verify(elements: ["Alice", "Carlos", "Donald"], changes: [], willChangeCount: 1, didChangeCount: 0)
        awaitIdle()
        verify(elements: ["Alice", "Bob", "Carlos", "Donald"], changes: [.insert(1)], willChangeCount: 1, didChangeCount: 1)
        observer.reset()
        
        verifySQLite(MakeRelation(
            ["id", "name"],
            [1,    "Alice"],
            [2,    "Donald"],
            [3,    "Carlos"],
            [4,    "Bob"]
        ))
        
        // Rename a person
        renamePerson(2, "Bon")
        verify(elements: ["Alice", "Bob", "Carlos", "Donald"], changes: [], willChangeCount: 1, didChangeCount: 0)
        awaitIdle()
        verify(elements: ["Alice", "Bob", "Bon", "Carlos"], changes: [.move(srcIndex: 3, dstIndex: 2)], willChangeCount: 1, didChangeCount: 1)
        observer.reset()
        
        verifySQLite(MakeRelation(
            ["id", "name"],
            [1,    "Alice"],
            [2,    "Bon"],
            [3,    "Carlos"],
            [4,    "Bob"]
        ))

        // Delete a person
        deletePerson(1)
        verify(elements: ["Alice", "Bob", "Bon", "Carlos"], changes: [], willChangeCount: 1, didChangeCount: 0)
        awaitIdle()
        verify(elements: ["Bob", "Bon", "Carlos"], changes: [.delete(0)], willChangeCount: 1, didChangeCount: 1)
        observer.reset()
        
        verifySQLite(MakeRelation(
            ["id", "name"],
            [2,    "Bon"],
            [3,    "Carlos"],
            [4,    "Bob"]
        ))
        
        removal()
    }
    
    func testFullArray() {
        // TODO
    }
}
