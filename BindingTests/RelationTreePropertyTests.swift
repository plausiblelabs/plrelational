//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import libRelational
@testable import Binding

class RelationTreePropertyTests: BindingTestCase {

    func testInit() {
        let sqliteDB = makeDB().db
        let sqliteRelation = sqliteDB.createRelation("collection", scheme: ["id", "name", "parent", "order"]).ok!
        
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
        
        let tree = sqliteRelation.treeProperty()
        
        verifyTree(tree, [
            "Group1",
            "  Collection1",
            "    Child1",
            "    Child2",
            "  Page1",
            "  Page2",
            "Group2"
        ])
    }
    
    func testInsertMoveDelete() {
        let sqliteDB = makeDB().db
        let loggingDB = ChangeLoggingDatabase(sqliteDB)
        let db = TransactionalDatabase(loggingDB)

        XCTAssertNil(sqliteDB.createRelation("collection", scheme: ["id", "name", "parent", "order"]).err)
        let relation = db["collection"]
        let tree = relation.treeProperty()
        XCTAssertEqual(tree.root.children.count, 0)
        
        var changes: [RelationTreeProperty.Change] = []
        let removal = tree.signal.observe({ treeChanges, _ in
            changes.append(contentsOf: treeChanges)
        })
        
        func addCollection(_ collectionID: Int64, name: String, parentID: Int64?, previousID: Int64?) {
            db.transaction({
                let row: Row = [
                    "id": RelationValue(collectionID),
                    "name": RelationValue(name)
                ]
                let parent = parentID.map{RelationValue($0)}
                let previous = previousID.map{RelationValue($0)}
                let pos = RelationTreeProperty.Pos(parentID: parent, previousID: previous, nextID: nil)
                tree.insert(row, pos: pos)
            })
        }
        
        func deleteCollection(_ collectionID: Int64) {
            db.transaction({
                tree.delete(RelationValue(collectionID))
            })
        }
        
        func moveCollection(srcPath: RelationTreeProperty.Path, dstPath: RelationTreeProperty.Path) {
            db.transaction({
                tree.move(srcPath: srcPath, dstPath: dstPath)
            })
        }
        
        func verifyChanges(_ expected: [RelationTreeProperty.Change], file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(changes, expected, file: file, line: line)
            changes = []
        }
        
        func verifySQLite(_ expected: Relation, file: StaticString = #file, line: UInt = #line) {
            XCTAssertNil(loggingDB.save().err)
            AssertEqual(sqliteDB["collection"]!, expected, file: file, line: line)
        }
        
        func path(_ parentID: Int64?, _ index: Int) -> RelationTreeProperty.Path {
            let parent = parentID.flatMap{ tree.nodeForID(RelationValue($0)) }
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
        verifyTree(tree, [
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
        verifyTree(tree, [
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
        verifyTree(tree, [
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
        verifyTree(tree, [
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
        verifyTree(tree, [
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
    
    func testDeleteFromUnderlyingRelationsAndRestore() {
        let sqliteDB = makeDB().db
        let loggingDB = ChangeLoggingDatabase(sqliteDB)
        let db = TransactionalDatabase(loggingDB)
        
        func createRelation(_ name: String, _ scheme: Scheme) -> MutableRelation {
            let createResult = sqliteDB.createRelation(name, scheme: scheme)
            precondition(createResult.ok != nil)
            return db[name]
        }
        
        var objects = createRelation("object", ["id", "name", "type"])
        var docItems = createRelation("doc_item", ["id", "parent", "order"])
        var selectedDocItemID = createRelation("selected_doc_item", ["id"])
        
        let docObjects = docItems
            .join(objects)
        let tree = docObjects.treeProperty()
        XCTAssertEqual(tree.root.children.count, 0)
        
        var changes: [RelationTreeProperty.Change] = []
        let removal = tree.signal.observe({ treeChanges, _ in
            changes.append(contentsOf: treeChanges)
        })
        
        func verifyChanges(_ expected: [RelationTreeProperty.Change], file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(changes, expected, file: file, line: line)
            changes = []
        }
        
        func verifySQLite(_ expected: Relation, file: StaticString = #file, line: UInt = #line) {
            XCTAssertNil(loggingDB.save().err)
            AssertEqual(sqliteDB["collection"]!, expected, file: file, line: line)
        }
        
        func path(_ parentID: Int64?, _ index: Int) -> RelationTreeProperty.Path {
            let parent = parentID.flatMap{ tree.nodeForID(RelationValue($0)) }
            return TreePath(parent: parent, index: index)
        }
        
        func addDocItem(_ id: Int64, parentID: Int64?, previousID: Int64?) {
            var row: Row = ["id": RelationValue(id)]
            let parent = parentID.map{ RelationValue($0) }
            let previous = previousID.map{ RelationValue($0) }
            let pos: TreePos<RowTreeNode> = TreePos(parentID: parent, previousID: previous, nextID: nil)
            tree.computeOrderForInsert(&row, pos: pos)
            _ = docItems.add(row)
        }
        
        func addObject(_ id: Int64, name: String) {
            _ = objects.add([
                "id": RelationValue(id),
                "name": RelationValue(name),
                "type": RelationValue(Int64(0))
            ])
        }

        var globalID: Int64 = 1
        
        func newDocObject(_ name: String, parentID: Int64?) -> Int64 {
            let id = globalID
            db.transaction{
                addObject(id, name: name)
                addDocItem(id, parentID: parentID, previousID: nil)
            }
            globalID += 1
            return id
        }
        
        func addGroup(_ name: String, _ parentID: Int64?) -> Int64 {
            return newDocObject(name, parentID: parentID)
        }
        
        func addTextPage(_ name: String, _ parentID: Int64?) -> Int64 {
            return newDocObject(name, parentID: parentID)
        }
        
        func deleteDocObject(_ id: Int64) {
            db.transaction{
                let expr = Attribute("id") *== RelationValue(id)
                _ = objects.delete(expr)
                _ = docItems.delete(expr)
                _ = selectedDocItemID.delete(expr)
            }
        }
        
        // Insert some doc items
        let tg1 = addGroup("TopGroup1", nil)
        _ = addGroup("TopGroup2", nil)
        let ng = addGroup("NestedGroup", tg1)
        _ = addTextPage("Page1", tg1)
        let p2 = addTextPage("Page2", tg1)
        _ = addTextPage("NestedPage1", ng)
        _ = addTextPage("NestedPage2", ng)
        _ = addTextPage("NestedPage3", ng)
        
        verifyTree(tree, [
            "TopGroup1",
            "  NestedGroup",
            "    NestedPage1",
            "    NestedPage2",
            "    NestedPage3",
            "  Page1",
            "  Page2",
            "TopGroup2"
        ])
        verifyChanges([
            .insert(path(nil, 0)),
            .insert(path(nil, 1)),
            .insert(path(tg1, 0)),
            .insert(path(tg1, 1)),
            .insert(path(tg1, 2)),
            .insert(path(ng, 0)),
            .insert(path(ng, 1)),
            .insert(path(ng, 2))
        ])
        // TODO: Verify SQLite
        
        // Take a snapshot that we can restore later
        let preDelete = db.takeSnapshot()

        // Delete from the underlying relations
        deleteDocObject(p2)

        verifyTree(tree, [
            "TopGroup1",
            "  NestedGroup",
            "    NestedPage1",
            "    NestedPage2",
            "    NestedPage3",
            "  Page1",
            "TopGroup2"
            ])
        verifyChanges([
            .delete(path(tg1, 2)),
        ])
        // TODO: Verify SQLite
        
        // Undo the delete by restoring the previous snapshot
        db.restoreSnapshot(preDelete)
        
        verifyTree(tree, [
            "TopGroup1",
            "  NestedGroup",
            "    NestedPage1",
            "    NestedPage2",
            "    NestedPage3",
            "  Page1",
            "  Page2",
            "TopGroup2"
        ])
        verifyChanges([
            .insert(path(tg1, 2)),
        ])
        // TODO: Verify SQLite
    }
}
