//
//  OrderedTreeBindingTests.swift
//  Relational
//
//  Created by Chris Campbell on 5/11/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import XCTest
import libRelational
@testable import SampleApp

class OrderedTreeBindingTests: XCTestCase {

    var dbPaths: [String] = []
    
    override func tearDown() {
        for path in dbPaths {
            _ = try? NSFileManager.defaultManager().removeItemAtPath(path)
        }
    }
    
    func makeDB() -> (path: String, db: SQLiteDatabase) {
        let tmp = NSTemporaryDirectory() as NSString
        let dbname = "testing-\(NSUUID()).db"
        let path = tmp.stringByAppendingPathComponent(dbname)
        _ = try? NSFileManager.defaultManager().removeItemAtPath(path)
        
        let db = try! SQLiteDatabase(path)
        
        dbPaths.append(path)

        return (path, db)
    }
    
    func testInit() {
        let sqliteDB = makeDB().db
        let sqliteRelation = sqliteDB.createRelation("collection", scheme: ["id", "name", "parent", "order"]).ok!
        
        // Add some existing data to the underlying SQLite database
        func addCollection(collectionID: Int64, name: String, parentID: Int64?, order: Double) {
            let parent: RelationValue
            if let parentID = parentID {
                parent = RelationValue(parentID)
            } else {
                parent = .NULL
            }
            
            sqliteRelation.add([
                "id": RelationValue(collectionID),
                "name": RelationValue(name),
                "parent": parent,
                "order": RelationValue(order)
            ])
        }
        addCollection(1, name: "Group1", parentID: nil, order: 1.0)
        addCollection(2, name: "Collection1", parentID: 1, order: 1.0)
        addCollection(3, name: "Page1", parentID: 1, order: 2.0)
        addCollection(4, name: "Page2", parentID: 1, order: 3.0)
        addCollection(5, name: "Child1", parentID: 2, order: 1.0)
        addCollection(6, name: "Child2", parentID: 2, order: 1.0)
        addCollection(7, name: "Group2", parentID: nil, order: 2.0)
        
        let db = ChangeLoggingDatabase(sqliteDB)
        let relation = db["collection"]
        let treeBinding = OrderedTreeBinding(relation: relation, tableName: "collection", idAttr: "id", parentAttr: "parent", orderAttr: "order")
        
        // TODO: Verify that in-memory tree structure was built correctly during initialization
        //XCTAssertEqual(treeBinding.root.children.count, 2)
    }
    
    func testInsert() {
        let sqliteDB = makeDB().db
        let db = ChangeLoggingDatabase(sqliteDB)
        
        XCTAssertNil(sqliteDB.createRelation("collection", scheme: ["id", "name", "parent", "order"]).err)
        let relation = db["collection"]
        let treeBinding = OrderedTreeBinding(relation: relation, tableName: "collection", idAttr: "id", parentAttr: "parent", orderAttr: "order")
        XCTAssertEqual(treeBinding.root.children.count, 0)
        
        func addCollection(collectionID: Int64, name: String, parentID: Int64?, previousID: Int64?) {
            db.transaction({
                let row: Row = [
                    "id": RelationValue(collectionID),
                    "name": RelationValue(name)
                ]
                let parent = parentID.map{RelationValue($0)}
                let previous = previousID.map{RelationValue($0)}
                let pos = TreePos(parentID: parent, previousID: previous, nextID: nil)
                treeBinding.insert($0, row: row, pos: pos)
            })
        }
        
        addCollection(1, name: "Group1", parentID: nil, previousID: nil)
        addCollection(2, name: "Collection1", parentID: 1, previousID: nil)
        addCollection(3, name: "Page1", parentID: 1, previousID: 2)
        addCollection(4, name: "Page2", parentID: 1, previousID: 3)
        addCollection(5, name: "Child1", parentID: 2, previousID: nil)
        addCollection(6, name: "Child2", parentID: 2, previousID: 5)
        addCollection(7, name: "Group2", parentID: nil, previousID: 1)
        
        // Verify in-memory tree structure
        let root = treeBinding.root
        XCTAssertEqual(root.children.count, 2)
        XCTAssertEqual(root.children[0].data["name"], "Group1")
        XCTAssertEqual(root.children[1].data["name"], "Group2")
        let group1 = root.children[0]
        XCTAssertEqual(group1.children.count, 3)
        XCTAssertEqual(group1.children[0].data["name"], "Collection1")
        XCTAssertEqual(group1.children[1].data["name"], "Page1")
        XCTAssertEqual(group1.children[2].data["name"], "Page2")
        let group2 = root.children[1]
        XCTAssertEqual(group2.children.count, 0)
        let coll1 = group1.children[0]
        XCTAssertEqual(coll1.children.count, 2)
        XCTAssertEqual(coll1.children[0].data["name"], "Child1")
        XCTAssertEqual(coll1.children[1].data["name"], "Child2")
        
        // TODO: Call db.save() and verify SQLite table structure
    }
}
