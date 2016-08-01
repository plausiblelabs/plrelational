//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import libRelational
@testable import Binding

class RelationArrayPropertyTests: BindingTestCase {
    
    func testInit() {
        let sqliteDB = makeDB().db
        let sqliteRelation = sqliteDB.createRelation("page", scheme: ["id", "name", "order"]).ok!
        let db = TransactionalDatabase(sqliteDB)
        let r = db["page"]

        // Add some existing data to the underlying SQLite database
        func addPage(pageID: Int64, name: String, order: Double) {
            sqliteRelation.add([
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
        
        func awaitCompletion(f: () -> Void) {
            f()
            CFRunLoopRun()
        }
        
        var willChangeCount = 0
        var didChangeCount = 0
        var changes: [RelationArrayProperty.Change] = []

        let property = r.arrayProperty()
        let removal = property.signal.observe(SignalObserver(
            valueWillChange: {
                willChangeCount += 1
            },
            valueChanging: { arrayChanges, _ in
                changes.appendContentsOf(arrayChanges)
            },
            valueDidChange: {
                didChangeCount += 1
                CFRunLoopStop(runloop)
            }
        ))
        
        // Verify that property value remains nil until we actually start it
        XCTAssertNil(property.value)
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
    
    func testInsertMoveDelete() {
        let sqliteDB = makeDB().db
        let sqliteRelation = sqliteDB.createRelation("page", scheme: ["id", "name", "order"]).ok!
        let loggingDB = ChangeLoggingDatabase(sqliteDB)
        let db = TransactionalDatabase(loggingDB)
        let r = db["page"]
        
        let runloop = CFRunLoopGetCurrent()
        
        func awaitCompletion(f: () -> Void) {
            f()
            CFRunLoopRun()
        }
        
        var willChangeCount = 0
        var didChangeCount = 0
        var changes: [RelationArrayProperty.Change] = []
        
        let property = r.arrayProperty()
        let removal = property.signal.observe(SignalObserver(
            valueWillChange: {
                willChangeCount += 1
            },
            valueChanging: { arrayChanges, _ in
                changes.appendContentsOf(arrayChanges)
            },
            valueDidChange: {
                didChangeCount += 1
                CFRunLoopStop(runloop)
            }
        ))
        
        func addPage(pageID: Int64, name: String, previousID: Int64?) {
            let row: Row = [
                "id": RelationValue(pageID),
                "name": RelationValue(name)
            ]
            let previous = previousID.map{RelationValue($0)}
            let pos = RelationArrayProperty.Pos(previousID: previous, nextID: nil)
            property.insert(row, pos: pos)
        }
        
        func deletePage(pageID: Int64) {
            property.delete(RelationValue(pageID))
        }
        
        func movePage(srcIndex srcIndex: Int, dstIndex: Int) {
            property.move(srcIndex: srcIndex, dstIndex: dstIndex)
        }

        func verifyChanges(expected: [RelationArrayProperty.Change], file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(changes, expected, file: file, line: line)
            changes = []
        }

        func verifySQLite(expected: Relation, file: StaticString = #file, line: UInt = #line) {
            XCTAssertNil(loggingDB.save().err)
            AssertEqual(sqliteDB["page"]!, expected, file: file, line: line)
        }

        // Verify that property value remains nil until we actually start it
        XCTAssertNil(property.value)
        XCTAssertEqual(willChangeCount, 0)
        XCTAssertEqual(didChangeCount, 0)
        XCTAssertEqual(changes, [])

        // Verify that in-memory array structure is empty after property/signal was started
        awaitCompletion{ property.start() }
        XCTAssertEqual(willChangeCount, 1)
        XCTAssertEqual(didChangeCount, 1)
        verifyArray(property, [])
        verifyChanges([.Initial([])])
        
        // Insert some pages
        awaitCompletion{ addPage(1, name: "Page1", previousID: nil) }
        awaitCompletion{ addPage(2, name: "Page2", previousID: 1) }
        awaitCompletion{ addPage(3, name: "Page3", previousID: 2) }
        awaitCompletion{ addPage(4, name: "Page4", previousID: 3) }
        XCTAssertEqual(willChangeCount, 5)
        XCTAssertEqual(didChangeCount, 5)
        verifyArray(property, [
            "Page1",
            "Page2",
            "Page3",
            "Page4"
        ])
        verifyChanges([
            .Insert(0),
            .Insert(1),
            .Insert(2),
            .Insert(3),
        ])
        verifySQLite(MakeRelation(
            ["id", "name",  "order"],
            [1,    "Page1", 5.0],
            [2,    "Page2", 7.0],
            [3,    "Page3", 8.0],
            [4,    "Page4", 8.5]
        ))

        // TODO: The following tests are temporarily disabled while we make `move` async-safe
        
//        // Re-order a page
//        movePage(srcIndex: 2, dstIndex: 0)
//        verifyArray(array, [
//            "Page3",
//            "Page1",
//            "Page2",
//            "Page4"
//        ])
//        verifyChanges([
//            .Move(srcIndex: 2, dstIndex: 0)
//        ])
//        verifySQLite(MakeRelation(
//            ["id", "name",  "order"],
//            [1,    "Page1", 5.0],
//            [2,    "Page2", 7.0],
//            [3,    "Page3", 3.0],
//            [4,    "Page4", 8.5]
//        ))
//
//        // Delete a page
//        deletePage(1)
//        verifyArray(array, [
//            "Page3",
//            "Page2",
//            "Page4"
//        ])
//        verifyChanges([
//            .Delete(1)
//        ])
//        verifySQLite(MakeRelation(
//            ["id", "name",  "order"],
//            [2,    "Page2", 7.0],
//            [3,    "Page3", 3.0],
//            [4,    "Page4", 8.5]
//        ))
        
        removal()
    }
}
