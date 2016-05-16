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

// TODO: Import this from RelationalTests
public func AssertEqual(a: Relation, _ b: Relation, file: StaticString = #file, line: UInt = #line) {
    XCTAssertEqual(a.scheme, b.scheme, "Relation schemes are not equal", file: file, line: line)
    let aRows = mapOk(a.rows(), { $0 })
    let bRows = mapOk(b.rows(), { $0 })
    
    switch (aRows, bRows) {
    case (.Ok(let aRows), .Ok(let bRows)):
        let aSet = Set(aRows)
        let bSet = Set(bRows)
        XCTAssertEqual(aSet, bSet, "Relations are not equal but should be. First relation:\n\(a)\n\nSecond relation:\n\(b)", file: file, line: line)
    default:
        XCTAssertNil(aRows.err)
        XCTAssertNil(bRows.err)
    }
}

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
    
    func pretty(node: OrderedTreeBinding.Node, _ accum: String, _ indent: Int) -> String {
        var mutstr = accum
        let pad = Array(count: indent, repeatedValue: "  ").joinWithSeparator("")
        mutstr.appendContentsOf("\(pad)\(node.data["name"])\n")
        for child in node.children {
            mutstr = pretty(child, mutstr, indent + 1)
        }
        return mutstr
    }
    
    func prettyRoot(binding: OrderedTreeBinding) -> String {
        var s = ""
        for node in binding.root.children {
            s = pretty(node, s, 0)
        }
        return s
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
        
        func verifyTree(expected: [String]) {
            let s = "\(expected.joinWithSeparator("\n"))\n"
            XCTAssertEqual(prettyRoot(treeBinding), s)
        }

        // TODO: Verify that in-memory tree structure was built correctly during initialization
//        verifyTree([
//            "Group1",
//            "  Collection1",
//            "    Child1",
//            "    Child2",
//            "    Child3",
//            "  Page1",
//            "  Page2",
//            "Group2"
//        ])
    }
    
    func testInsertMoveDelete() {
        let sqliteDB = makeDB().db
        let db = ChangeLoggingDatabase(sqliteDB)
        
        XCTAssertNil(sqliteDB.createRelation("collection", scheme: ["id", "name", "parent", "order"]).err)
        let relation = db["collection"]
        let treeBinding = OrderedTreeBinding(relation: relation, tableName: "collection", idAttr: "id", parentAttr: "parent", orderAttr: "order")
        XCTAssertEqual(treeBinding.root.children.count, 0)
        
        var changes: [OrderedTreeBinding.Change] = []
        let removal = treeBinding.addChangeObserver({ treeChanges in
            changes.appendContentsOf(treeChanges)
        })
        
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
        
        func deleteCollection(collectionID: Int64) {
            db.transaction({
                treeBinding.delete($0, id: RelationValue(collectionID))
            })
        }
        
        func moveCollection(srcPath srcPath: TreePath, dstPath: TreePath) {
            db.transaction({
                treeBinding.move($0, srcPath: srcPath, dstPath: dstPath)
            })
        }
        
        func verifyTree(expected: [String]) {
            let s = "\(expected.joinWithSeparator("\n"))\n"
            XCTAssertEqual(prettyRoot(treeBinding), s)
        }
        
        func verifyChanges(expected: [OrderedTreeBinding.Change]) {
            XCTAssertEqual(changes, expected)
            changes = []
        }
        
        func verifySQLite(expected: Relation) {
            XCTAssertNil(db.save().err)
            AssertEqual(sqliteDB["collection"]!, expected)
        }
        
        func path(parentID: Int64?, _ index: Int) -> TreePath {
            let parent = parentID.flatMap{ treeBinding.nodeForID(RelationValue($0)) }
            return TreePath(parent: parent, index: index)
        }
        
        // Insert some collections
        addCollection(1, name: "Group1", parentID: nil, previousID: nil)
        addCollection(2, name: "Collection1", parentID: 1, previousID: nil)
        addCollection(3, name: "Page1", parentID: 1, previousID: 2)
        addCollection(4, name: "Page2", parentID: 1, previousID: 3)
        addCollection(5, name: "Child1", parentID: 2, previousID: nil)
        addCollection(6, name: "Child2", parentID: 2, previousID: 5)
        addCollection(7, name: "Child3", parentID: 2, previousID: 6)
        addCollection(8, name: "Group2", parentID: nil, previousID: 1)
        verifyTree([
            "Group1",
            "  Collection1",
            "    Child1",
            "    Child2",
            "    Child3",
            "  Page1",
            "  Page2",
            "Group2"
        ])
        verifyChanges([
            .Insert(path(nil, 0)),
            .Insert(path(1, 0)),
            .Insert(path(1, 1)),
            .Insert(path(1, 2)),
            .Insert(path(2, 0)),
            .Insert(path(2, 1)),
            .Insert(path(2, 2)),
            .Insert(path(nil, 1)),
        ])
        verifySQLite(MakeRelation(
            ["id", "name", "parent", "order"],
            [1, "Group1",      .NULL, 5.0],
            [2, "Collection1", 1,     5.0],
            [3, "Page1",       1,     7.0],
            [4, "Page2",       1,     8.0],
            [5, "Child1",      2,     5.0],
            [6, "Child2",      2,     7.0],
            [7, "Child3",      2,     8.0],
            [8, "Group2",      .NULL, 7.0]
        ))

        // Re-order a collection within its parent
        moveCollection(srcPath: path(2, 2), dstPath: path(2, 0))
        verifyTree([
            "Group1",
            "  Collection1",
            "    Child3",
            "    Child1",
            "    Child2",
            "  Page1",
            "  Page2",
            "Group2"
        ])
        verifyChanges([
            .Move(src: path(2, 2), dst: path(2, 0))
        ])
        verifySQLite(MakeRelation(
            ["id", "name", "parent", "order"],
            [1, "Group1",      .NULL, 5.0],
            [2, "Collection1", 1,     5.0],
            [3, "Page1",       1,     7.0],
            [4, "Page2",       1,     8.0],
            [5, "Child1",      2,     5.0],
            [6, "Child2",      2,     7.0],
            [7, "Child3",      2,     3.0],
            [8, "Group2",      .NULL, 7.0]
        ))
        
        // Move a collection to a new parent
        moveCollection(srcPath: path(1, 0), dstPath: path(8, 0))
        verifyTree([
            "Group1",
            "  Page1",
            "  Page2",
            "Group2",
            "  Collection1",
            "    Child3",
            "    Child1",
            "    Child2"
        ])
        verifyChanges([
            .Move(src: path(1, 0), dst: path(8, 0))
        ])
        verifySQLite(MakeRelation(
            ["id", "name", "parent", "order"],
            [1, "Group1",      .NULL, 5.0],
            [2, "Collection1", 8,     5.0],
            [3, "Page1",       1,     7.0],
            [4, "Page2",       1,     8.0],
            [5, "Child1",      2,     5.0],
            [6, "Child2",      2,     7.0],
            [7, "Child3",      2,     3.0],
            [8, "Group2",      .NULL, 7.0]
        ))
        
        // Move a collection to the top level
        moveCollection(srcPath: path(2, 1), dstPath: path(nil, 1))
        verifyTree([
            "Group1",
            "  Page1",
            "  Page2",
            "Child1",
            "Group2",
            "  Collection1",
            "    Child3",
            "    Child2"
        ])
        verifyChanges([
            .Move(src: path(2, 1), dst: path(nil, 1))
        ])
        verifySQLite(MakeRelation(
            ["id", "name", "parent", "order"],
            [1, "Group1",      .NULL, 5.0],
            [2, "Collection1", 8,     5.0],
            [3, "Page1",       1,     7.0],
            [4, "Page2",       1,     8.0],
            [5, "Child1",      .NULL, 6.0],
            [6, "Child2",      2,     7.0],
            [7, "Child3",      2,     3.0],
            [8, "Group2",      .NULL, 7.0]
        ))
        
        // Delete a couple collections
        deleteCollection(4)
        deleteCollection(2)
        verifyTree([
            "Group1",
            "  Page1",
            "Child1",
            "Group2"
        ])
        verifyChanges([
            .Delete(path(1, 1)),
            .Delete(path(8, 0))
        ])
        verifySQLite(MakeRelation(
            ["id", "name", "parent", "order"],
            [1, "Group1",      .NULL, 5.0],
            [3, "Page1",       1,     7.0],
            [5, "Child1",      .NULL, 6.0],
            [8, "Group2",      .NULL, 7.0]
        ))
    }
}
