//
//  RelationArrayBindingTests.swift
//  Relational
//
//  Created by Chris Campbell on 5/23/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import XCTest
import libRelational
@testable import SampleApp

class RelationArrayBindingTests: AppTestCase {
    
    func testInit() {
        let sqliteDB = makeDB().db
        let sqliteRelation = sqliteDB.createRelation("page", scheme: ["id", "name", "order"]).ok!
        
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
        
        let arrayBinding = RelationArrayBinding(relation: sqliteRelation, idAttr: "id", orderAttr: "order")
        
        // TODO: Verify that in-memory array structure was built correctly during initialization
//        verifyArray(arrayBinding, [
//            "Page1",
//            "Page2",
//            "Page3",
//            "Page4"
//        ])
    }
    
    func testInsertMoveDelete() {
        let sqliteDB = makeDB().db
        let loggingDB = ChangeLoggingDatabase(sqliteDB)
        let db = TransactionalDatabase(loggingDB)
        
        XCTAssertNil(sqliteDB.createRelation("page", scheme: ["id", "name", "order"]).err)
        let relation = db["page"]
        let arrayBinding = RelationArrayBinding(relation: relation, idAttr: "id", orderAttr: "order")
        XCTAssertEqual(arrayBinding.elements.count, 0)
        
        var changes: [RelationArrayBinding.Change] = []
        let removal = arrayBinding.addChangeObserver({ arrayChanges in
            changes.appendContentsOf(arrayChanges)
        })
        
        func addPage(pageID: Int64, name: String, previousID: Int64?) {
            db.transaction({
                let row: Row = [
                    "id": RelationValue(pageID),
                    "name": RelationValue(name)
                ]
                let previous = previousID.map{RelationValue($0)}
                let pos = RelationArrayBinding.Pos(previousID: previous, nextID: nil)
                arrayBinding.insert(row, pos: pos)
            })
        }
        
        func deletePage(pageID: Int64) {
            db.transaction({
                arrayBinding.delete(RelationValue(pageID))
            })
        }
        
        func movePage(srcIndex srcIndex: Int, dstIndex: Int) {
            db.transaction({
                arrayBinding.move(srcIndex: srcIndex, dstIndex: dstIndex)
            })
        }
        
        func verifyChanges(expected: [RelationArrayBinding.Change], file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(changes, expected, file: file, line: line)
            changes = []
        }
        
        func verifySQLite(expected: Relation, file: StaticString = #file, line: UInt = #line) {
            XCTAssertNil(loggingDB.save().err)
            AssertEqual(sqliteDB["page"]!, expected, file: file, line: line)
        }
        
//        // Insert some pages
//        addPage(1, name: "Page1", previousID: nil)
//        addPage(2, name: "Page2", previousID: 1)
//        addPage(3, name: "Page3", previousID: 2)
//        addPage(4, name: "Page4", previousID: 3)
//        verifyArray(arrayBinding, [
//            "Page1",
//            "Page2",
//            "Page3",
//            "Page4"
//        ])
//        verifyChanges([
//            .Insert(0),
//            .Insert(1),
//            .Insert(2),
//            .Insert(3),
//        ])
//        verifySQLite(MakeRelation(
//            ["id", "name",  "order"],
//            [1,    "Page1", 5.0],
//            [2,    "Page2", 7.0],
//            [3,    "Page3", 8.0],
//            [4,    "Page4", 8.5]
//        ))
//        
//        // Re-order a page
//        movePage(srcIndex: 2, dstIndex: 0)
//        verifyArray(arrayBinding, [
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
//        verifyArray(arrayBinding, [
//            "Page3",
//            "Page2",
//            "Page4"
//        ])
//        verifyChanges([
//            .Delete(1)
//        ])
//        verifySQLite(MakeRelation(
//            ["id", "name",  "order"],
//            [1,    "Page1", 5.0],
//            [2,    "Page2", 7.0],
//            [4,    "Page4", 8.5]
//        ))
    }
}
