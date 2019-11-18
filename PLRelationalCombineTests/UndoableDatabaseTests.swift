//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import PLRelational
import PLRelationalCombine

class UndoableDatabaseTests: CombineTestCase {
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

        let undoManager = PLRelationalCombine.UndoManager()
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

    func testOneString() {
        let sqlite = makeDB().db
        XCTAssertNil(sqlite.getOrCreateRelation("r", scheme: ["name"]).err)

        let db = TransactionalDatabase(sqlite)
        let persons = db["r"]
        _ = persons.add(["name": "Abraham"])

        let undoManager = PLRelationalCombine.UndoManager()
        let undoableDB = UndoableDatabase(db: db, undoManager: undoManager)

        class TestViewModel: ObservableObject {
            @TwoWay(onSet: .commit) var name: String = ""
            private var cancellableBag = CancellableBag()
            
            init(_ persons: Relation, _ undoableDB: UndoableDatabase) {
                persons
                    .project("name")
                    .bind(to: \._name, on: self, strategy: undoableDB.oneString("Change Name"))
                    .store(in: &cancellableBag)
            }
            
            deinit {
                cancellableBag.cancel()
            }
        }
        
        let vm = TestViewModel(persons, undoableDB)
        awaitIdle()
        XCTAssertEqual(vm.name, "Abraham")
        
        vm.name = "Abe"
        awaitIdle()
        XCTAssertEqual(vm.name, "Abe")

        undoManager.undo()
        awaitIdle()
        XCTAssertEqual(vm.name, "Abraham")
    }
    
    func testOneBool() {
        let sqlite = makeDB().db
        XCTAssertNil(sqlite.getOrCreateRelation("r", scheme: ["name", "cool"]).err)

        let db = TransactionalDatabase(sqlite)
        let persons = db["r"]
        _ = persons.add(["name": "Abraham", "cool": 1])

        let undoManager = PLRelationalCombine.UndoManager()
        let undoableDB = UndoableDatabase(db: db, undoManager: undoManager)

        class TestViewModel: ObservableObject {
            @TwoWay(onSet: .commit) var cool: Bool = false
            private var cancellableBag = CancellableBag()
            
            init(_ persons: Relation, _ undoableDB: UndoableDatabase) {
                persons
                    .project("cool")
                    .bind(to: \._cool, on: self, strategy: undoableDB.oneBool("Change Coolness"))
                    .store(in: &cancellableBag)
            }
            
            deinit {
                cancellableBag.cancel()
            }
        }
        
        let vm = TestViewModel(persons, undoableDB)
        awaitIdle()
        XCTAssertEqual(vm.cool, true)
        
        vm.cool = false
        awaitIdle()
        XCTAssertEqual(vm.cool, false)

        undoManager.undo()
        awaitIdle()
        XCTAssertEqual(vm.cool, true)
    }
}
