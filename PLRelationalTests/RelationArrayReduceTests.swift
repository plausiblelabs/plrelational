//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import PLRelational
@testable import PLRelationalCombine

class RelationArrayReduceTests: CombineTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }
    
    func testInsertRenameDeleteSortedByName() {
        let sqliteDB = makeDB().db
        let sqliteRelation = sqliteDB.createRelation("person", scheme: ["id", "name"]).ok!
        let loggingDB = ChangeLoggingDatabase(sqliteDB)
        let db = TransactionalDatabase(loggingDB)
        let r = db["person"]

        func row(_ id: Int64, _ name: String) -> Row {
            return [
                "id": RelationValue(id),
                "name": RelationValue(name)
            ]
        }
        
        // Add one person synchronously so that there is initial data supplied by the publisher
        _ = sqliteRelation.add(row(1, "Alice"))

        func addPerson(_ personID: Int64, _ name: String) {
            r.asyncAdd(row(personID, name))
        }

        func deletePerson(_ personID: Int64) {
            r.asyncDelete(Attribute("id") *== RelationValue(personID))
        }

        func renamePerson(_ personID: Int64, _ name: String) {
            r.asyncUpdate(Attribute("id") *== RelationValue(personID), newValues: ["name": RelationValue(name)])
        }

        func verifySQLite(_ expected: Relation, file: StaticString = #file, line: UInt = #line) {
            XCTAssertNil(loggingDB.save().err)
            AssertEqual(sqliteDB["person"]!, expected, file: file, line: line)
        }

        struct TestItem: Identifiable, Equatable, CustomStringConvertible {
            let id: RelationValue
            let name: String
            let tag: Int
            
            var description: String {
                "Item(\(id.get()! as Int64), \(name), \(tag))"
            }
        }
        
        func item(_ id: Int64, _ name: String, _ tag: Int) -> TestItem {
            return TestItem(id: RelationValue(id), name: name, tag: tag)
        }
        
        class TestViewModel {
            var expectation: XCTestExpectation!

            init() {
                self.reset()
            }
            
            func reset() {
                expectation = XCTestExpectation(description: "Items updated")
            }
            
            var items: [TestItem] = [] {
                didSet {
                    expectation.fulfill()
                }
            }
        }

        let vm = TestViewModel()

        func reset() {
            vm.reset()
        }
        
        func await() {
            wait(for: [vm.expectation], timeout: 5.0)
        }

        func verify(_ expectedItems: [TestItem], file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(vm.items, expectedItems, file: file, line: line)
        }
        
        // Subscribe to the relation change publisher
        var tag = 0
        let cancellable = r
            .changes()
            // TODO: Figure out better error handling approach for these publishers/subscribers
            .replaceError(with: RelationChangeSummary(added: [], updated: [], deleted: []))
            .reduce(to: \.items, on: vm, sortedBy: \.name) { row in
                tag += 1
                return TestItem(id: row["id"], name: row["name"].get()!, tag: tag)
            }
        XCTAssertNotNil(cancellable)

        // Verify that initial query produces Alice
        await()
        verify([
            item(1, "Alice", 1)
        ])

        // Insert some persons
        reset()
        addPerson(2, "Donald")
        await()
        verify([
            item(1, "Alice", 1),
            item(2, "Donald", 2)
        ])

        reset()
        addPerson(3, "Carlos")
        await()
        verify([
            item(1, "Alice", 1),
            item(3, "Carlos", 3),
            item(2, "Donald", 2)
        ])

        reset()
        addPerson(4, "Bob")
        await()
        verify([
            item(1, "Alice", 1),
            item(4, "Bob", 4),
            item(3, "Carlos", 3),
            item(2, "Donald", 2)
        ])

        verifySQLite(MakeRelation(
            ["id", "name"],
            [1,    "Alice"],
            [2,    "Donald"],
            [3,    "Carlos"],
            [4,    "Bob"]
        ))
        
        // Rename a person
        reset()
        renamePerson(2, "Bon")
        await()
        verify([
            item(1, "Alice", 1),
            item(4, "Bob", 4),
            item(2, "Bon", 5), // TODO: If we allow by-reference updates to items, the tag value might not change here
            item(3, "Carlos", 3)
        ])

        verifySQLite(MakeRelation(
            ["id", "name"],
            [1,    "Alice"],
            [2,    "Bon"],
            [3,    "Carlos"],
            [4,    "Bob"]
        ))

        // Delete a person
        reset()
        deletePerson(1)
        await()
        verify([
            item(4, "Bob", 4),
            item(2, "Bon", 5),
            item(3, "Carlos", 3)
        ])

        verifySQLite(MakeRelation(
            ["id", "name"],
            [2,    "Bon"],
            [3,    "Carlos"],
            [4,    "Bob"]
        ))

        // Perform multiple inserts/updates/deletes within a single transaction
        reset()
        deletePerson(2)
        addPerson(5, "Cate")
        renamePerson(4, "Bobby")
        await()
        verify([
            item(4, "Bobby", 7),
            item(3, "Carlos", 3),
            item(5, "Cate", 6)
        ])

        verifySQLite(MakeRelation(
            ["id", "name"],
            [3,    "Carlos"],
            [4,    "Bobby"],
            [5,    "Cate"]
        ))
        
        // TODO: Test in-place updates vs replace

        cancellable.cancel()
    }
}
