//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import libRelational
@testable import Binding

class RelationTreePropertyTests: BindingTestCase {

    private typealias Pos = TreePos<RowTreeNode>
    private typealias Path = TreePath<RowTreeNode>
    private typealias Change = TreeChange<RowTreeNode>

    func testInit() {
        let sqliteDB = makeDB().db
        let sqliteRelation = sqliteDB.createRelation("collection", scheme: ["id", "name", "parent", "order"]).ok!
        let db = TransactionalDatabase(sqliteDB)
        let r = db["collection"]

        // Add some existing data to the underlying SQLite database
        func addCollection(_ collectionID: Int64, name: String, parentID: Int64?, order: Double) {
            let parent: RelationValue
            if let parentID = parentID {
                parent = RelationValue(parentID)
            } else {
                parent = .null
            }
            
            _ = sqliteRelation.add([
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
        addCollection(6, name: "Child2", parentID: 2, order: 2.0)
        addCollection(7, name: "Group2", parentID: nil, order: 2.0)
        
        let runloop = CFRunLoopGetCurrent()
        
        func awaitCompletion(f: () -> Void) {
            f()
            CFRunLoopRun()
        }
        
        var willChangeCount = 0
        var didChangeCount = 0
        var changes: [Change] = []
        
        let property = r.treeProperty(idAttr: "id", parentAttr: "parent", orderAttr: "order")
        let removal = property.signal.observe(SignalObserver(
            valueWillChange: {
                willChangeCount += 1
            },
            valueChanging: { treeChanges, _ in
                changes.append(contentsOf: treeChanges)
            },
            valueDidChange: {
                didChangeCount += 1
                CFRunLoopStop(runloop)
            }
        ))
        
        // Verify that property value remains empty until we actually start it
        XCTAssertEqual(property.root.children.count, 0)
        XCTAssertEqual(willChangeCount, 0)
        XCTAssertEqual(didChangeCount, 0)
        XCTAssertEqual(changes, [])
        
        // Verify that in-memory array structure was built correctly after property/signal was started
        awaitCompletion{ property.start() }
        verifyTree(property, [
            "Group1",
            "  Collection1",
            "    Child1",
            "    Child2",
            "  Page1",
            "  Page2",
            "Group2"
        ])
        XCTAssertEqual(willChangeCount, 1)
        XCTAssertEqual(didChangeCount, 1)
        // TODO
        //XCTAssertEqual(changes, [])
        
        removal()
    }
    
    func testInsertMoveDelete() {
        let sqliteDB = makeDB().db
        let sqliteRelation = sqliteDB.createRelation("collection", scheme: ["id", "name", "parent", "order"]).ok!
        let loggingDB = ChangeLoggingDatabase(sqliteDB)
        let db = TransactionalDatabase(loggingDB)
        let r = db["collection"]

        let runloop = CFRunLoopGetCurrent()
        
        func awaitCompletion(f: () -> Void) {
            f()
            CFRunLoopRun()
        }
        
        var willChangeCount = 0
        var didChangeCount = 0
        var changes: [Change] = []
        
        let property = r.treeProperty(idAttr: "id", parentAttr: "parent", orderAttr: "order")
        let removal = property.signal.observe(SignalObserver(
            valueWillChange: {
                willChangeCount += 1
            },
            valueChanging: { treeChanges, _ in
                changes.append(contentsOf: treeChanges)
            },
            valueDidChange: {
                didChangeCount += 1
                CFRunLoopStop(runloop)
            }
        ))

        func addCollection(_ collectionID: Int64, name: String, parentID: Int64?) {
            let parent = parentID.map{RelationValue($0)}
            let order = property.orderForAppend(inParent: parent)
            let row: Row = [
                "id": RelationValue(collectionID),
                "name": RelationValue(name),
                "parent": parent ?? .null,
                "order": RelationValue(order)
            ]
            awaitCompletion{
                r.asyncAdd(row)
            }
        }
        
        func deleteCollection(_ collectionID: Int64) {
            awaitCompletion{
                r.treeDelete(
                    Attribute("id") *== RelationValue(collectionID),
                    parentAttribute: "id",
                    childAttribute: "parent",
                    completionCallback: { _ in })
            }
        }
        
        func moveCollection(srcPath: Path, dstPath: Path) {
            let (nodeID, dstParentID, order) = property.orderForMove(srcPath: srcPath, dstPath: dstPath)
            
            awaitCompletion{
                r.asyncUpdate(Attribute("id") *== nodeID, newValues: [
                    "parent": dstParentID ?? .null,
                    "order": RelationValue(order)
                ])
            }
        }
        
        func verifyChanges(_ expected: [Change], file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(changes, expected, file: file, line: line)
            changes = []
        }
        
        func verifySQLite(_ expected: Relation, file: StaticString = #file, line: UInt = #line) {
            XCTAssertNil(loggingDB.save().err)
            AssertEqual(sqliteDB["collection"]!, expected, file: file, line: line)
        }
        
        func path(_ parentID: Int64?, _ index: Int) -> Path {
            let parent = parentID.flatMap{ property.nodeForID(RelationValue($0)) }
            return TreePath(parent: parent, index: index)
        }
        
        // Verify that property value remains empty until we actually start it
        XCTAssertEqual(property.value!.children.count, 0)
        XCTAssertEqual(willChangeCount, 0)
        XCTAssertEqual(didChangeCount, 0)
        XCTAssertEqual(changes, [])

        // Verify that in-memory tree structure is empty after property/signal was started
        awaitCompletion{ property.start() }
        XCTAssertEqual(property.value!.children.count, 0)
        XCTAssertEqual(willChangeCount, 1)
        XCTAssertEqual(didChangeCount, 1)
        verifyChanges([.initial(property.value!)])

        // Insert some collections
        // TODO: The following only uses orderForAppend; need to exercise orderForInsert too
        addCollection(1, name: "Group1", parentID: nil)
        addCollection(2, name: "Collection1", parentID: 1)
        addCollection(3, name: "Page1", parentID: 1)
        addCollection(4, name: "Page2", parentID: 1)
        addCollection(5, name: "Child1", parentID: 2)
        addCollection(6, name: "Child2", parentID: 2)
        addCollection(7, name: "Child3", parentID: 2)
        addCollection(8, name: "Group2", parentID: nil)
        verifyTree(property, [
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
            .insert(path(nil, 0)),
            .insert(path(1, 0)),
            .insert(path(1, 1)),
            .insert(path(1, 2)),
            .insert(path(2, 0)),
            .insert(path(2, 1)),
            .insert(path(2, 2)),
            .insert(path(nil, 1)),
        ])
        verifySQLite(MakeRelation(
            ["id", "name", "parent", "order"],
            [1, "Group1",      .null, 5.0],
            [2, "Collection1", 1,     5.0],
            [3, "Page1",       1,     7.0],
            [4, "Page2",       1,     8.0],
            [5, "Child1",      2,     5.0],
            [6, "Child2",      2,     7.0],
            [7, "Child3",      2,     8.0],
            [8, "Group2",      .null, 7.0]
        ))

        // Re-order a collection within its parent
        moveCollection(srcPath: path(2, 2), dstPath: path(2, 0))
        verifyTree(property, [
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
            .move(src: path(2, 2), dst: path(2, 0))
        ])
        verifySQLite(MakeRelation(
            ["id", "name", "parent", "order"],
            [1, "Group1",      .null, 5.0],
            [2, "Collection1", 1,     5.0],
            [3, "Page1",       1,     7.0],
            [4, "Page2",       1,     8.0],
            [5, "Child1",      2,     5.0],
            [6, "Child2",      2,     7.0],
            [7, "Child3",      2,     3.0],
            [8, "Group2",      .null, 7.0]
        ))

        // Move a collection to a new parent
        moveCollection(srcPath: path(1, 0), dstPath: path(8, 0))
        verifyTree(property, [
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
            .move(src: path(1, 0), dst: path(8, 0))
        ])
        verifySQLite(MakeRelation(
            ["id", "name", "parent", "order"],
            [1, "Group1",      .null, 5.0],
            [2, "Collection1", 8,     5.0],
            [3, "Page1",       1,     7.0],
            [4, "Page2",       1,     8.0],
            [5, "Child1",      2,     5.0],
            [6, "Child2",      2,     7.0],
            [7, "Child3",      2,     3.0],
            [8, "Group2",      .null, 7.0]
        ))

        // Move a collection to the top level
        moveCollection(srcPath: path(2, 1), dstPath: path(nil, 1))
        verifyTree(property, [
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
            .move(src: path(2, 1), dst: path(nil, 1))
        ])
        verifySQLite(MakeRelation(
            ["id", "name", "parent", "order"],
            [1, "Group1",      .null, 5.0],
            [2, "Collection1", 8,     5.0],
            [3, "Page1",       1,     7.0],
            [4, "Page2",       1,     8.0],
            [5, "Child1",      .null, 6.0],
            [6, "Child2",      2,     7.0],
            [7, "Child3",      2,     3.0],
            [8, "Group2",      .null, 7.0]
        ))

        // Delete a couple collections
        deleteCollection(4)
        deleteCollection(2)
        verifyTree(property, [
            "Group1",
            "  Page1",
            "Child1",
            "Group2"
        ])
        verifyChanges([
            .delete(path(1, 1)),
            .delete(path(8, 0))
        ])
        verifySQLite(MakeRelation(
            ["id", "name", "parent", "order"],
            [1, "Group1",      .null, 5.0],
            [3, "Page1",       1,     7.0],
            [5, "Child1",      .null, 6.0],
            [8, "Group2",      .null, 7.0]
        ))
    }
}
