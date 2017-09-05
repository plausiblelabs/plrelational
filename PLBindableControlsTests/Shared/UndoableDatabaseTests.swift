//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import PLBindableControls
import PLRelational
import PLRelationalBinding

class UndoableDatabaseTests: BindingTestCase {
    func testTreeDelete() {
        let sqlite = makeDB().db
        XCTAssertNil(sqlite.getOrCreateRelation("r", scheme: ["id", "parent"]).err)
        
        let db = TransactionalDatabase(sqlite)
        let r = db["r"]
        
        let testData = MakeRelation(["id", "parent"],
                                    [1, .null],
                                    [2, .null],
                                    [3, .null],
                                    [4, .null],
                                    [10, 1],
                                    [11, 1],
                                    [12, 1],
                                    [100, 10],
                                    [101, 10],
                                    [110, 11],
                                    [1100, 110],
                                    [20, 2],
                                    [21, 2],
                                    [22, 2],
                                    [200, 20],
                                    [201, 20],
                                    [210, 21],
                                    [2100, 210],
                                    [30, 3],
                                    [31, 3],
                                    [32, 3],
                                    [300, 30],
                                    [301, 30],
                                    [310, 31],
                                    [3100, 310],
                                    [40, 4],
                                    [41, 4],
                                    [42, 4],
                                    [400, 40],
                                    [401, 40],
                                    [410, 41],
                                    [4100, 410])
        
        for row in testData.rows() {
                XCTAssertNil(r.add(row.ok!).err)
        }
        
        let undoManager = PLBindableControls.UndoManager()
        let undoableDB = UndoableDatabase(db: db, undoManager: undoManager)
        
        let group = DispatchGroup()
        group.enter()
        undoableDB.performUndoableAction("stuff", before: nil, {
            r.treeDelete(Attribute("id") *== 1 *|| Attribute("id") *== 2 *|| Attribute("id") *== 30, parentAttribute: "id", childAttribute: "parent", completionCallback: { result in
                XCTAssertNil(result.err)
                AsyncManager.currentInstance.registerCheckpoint({
                    group.leave()
                })
            })
        })
        let runloop = CFRunLoopGetCurrent()!
        group.notify(queue: DispatchQueue.global(), execute: { runloop.async({ CFRunLoopStop(runloop) }) })
        CFRunLoopRun()
        
        let expectedRemaining = MakeRelation(
            ["id", "parent"],
            [3, .null],
            [4, .null],
            [31, 3],
            [32, 3],
            [310, 31],
            [3100, 310],
            [40, 4],
            [41, 4],
            [42, 4],
            [400, 40],
            [401, 40],
            [410, 41],
            [4100, 410]
        )
        
        AssertEqual(r, expectedRemaining)
        
        undoManager.undo()
        group.enter()
        AsyncManager.currentInstance.registerCheckpoint({
            group.leave()
        })
        group.notify(queue: DispatchQueue.global(), execute: { runloop.async({ CFRunLoopStop(runloop) }) })
        CFRunLoopRun()
        
        AssertEqual(r, testData)
    }
    
    func testAllRelationValues() {
        let sqlite = makeDB().db
        XCTAssertNil(sqlite.getOrCreateRelation("r", scheme: ["name"]).err)
        
        let db = TransactionalDatabase(sqlite)
        let r = db["r"]
        _ = r.add(["name": "Alice"])
        _ = r.add(["name": "Bob"])
        _ = r.add(["name": "Chuck"])
        
        let undoManager = PLBindableControls.UndoManager()
        let undoableDB = UndoableDatabase(db: db, undoManager: undoManager)
        
        let property = r.undoableAllRelationValues(undoableDB, "Change Names")
        
        property.start()
        awaitIdle()
        XCTAssertEqual(property.value!, ["Alice", "Bob", "Chuck"])

        // XXX: This is a quick-and-dirty way of poking new values into `property`
        let tmp: MutableValueProperty<Set<RelationValue>> = mutableValueProperty([])
        let binding = tmp <~> property
        tmp.change(["Fred"])
        binding.unbind()
        awaitIdle()
        XCTAssertEqual(property.value!, ["Fred"])
        
        undoManager.undo()
        awaitIdle()
        XCTAssertEqual(property.value!, ["Alice", "Bob", "Chuck"])
    }
    
    func testOneString() {
        let sqlite = makeDB().db
        XCTAssertNil(sqlite.getOrCreateRelation("r", scheme: ["name"]).err)
        
        let db = TransactionalDatabase(sqlite)
        let r = db["r"]
        _ = r.add(["name": "Abraham"])
        
        let undoManager = PLBindableControls.UndoManager()
        let undoableDB = UndoableDatabase(db: db, undoManager: undoManager)
        
        let property = r.undoableOneString(undoableDB, "Change Name")

        property.start()
        awaitIdle()
        XCTAssertEqual(property.value!, "Abraham")
        
        // XXX: This is a quick-and-dirty way of poking new values into `property`
        let tmp: MutableValueProperty<String> = mutableValueProperty("")
        let binding = tmp <~> property
        tmp.change("Abe")
        binding.unbind()
        awaitIdle()
        XCTAssertEqual(property.value!, "Abe")
        
        undoManager.undo()
        awaitIdle()
        XCTAssertEqual(property.value!, "Abraham")
    }
    
    func testTransformedString() {
        let sqlite = makeDB().db
        XCTAssertNil(sqlite.getOrCreateRelation("r", scheme: ["num"]).err)
        
        let db = TransactionalDatabase(sqlite)
        let r = db["r"]
        _ = r.add(["num": "1"])
        
        let undoManager = PLBindableControls.UndoManager()
        let undoableDB = UndoableDatabase(db: db, undoManager: undoManager)
        
        let property = r.undoableTransformedString(undoableDB, "Change Number", fromString: { Int($0)! }, toString: { String($0) })
        
        property.start()
        awaitIdle()
        XCTAssertEqual(property.value!, 1)
        
        // XXX: This is a quick-and-dirty way of poking new values into `property`
        let tmp: MutableValueProperty<Int> = mutableValueProperty(0)
        let binding = tmp <~> property
        tmp.change(42)
        binding.unbind()
        awaitIdle()
        XCTAssertEqual(property.value!, 42)
        
        undoManager.undo()
        awaitIdle()
        XCTAssertEqual(property.value!, 1)
    }
}
