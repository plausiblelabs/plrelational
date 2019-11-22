//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import PLRelational
@testable import PLRelationalCombine

private struct TestItem: Identifiable, Equatable, CustomStringConvertible {
    let id: Int64
    let name: String

    init(id: Int64, name: String) {
        self.id = id
        self.name = name
    }

    init(row: Row) {
        self.init(id: row["id"].get()!, name: row["name"].get()!)
    }

    var description: String {
        "Item(\(id) \(name))"
    }
}

// XXX: Have to define this outside the test function due to:
//   SR-3092: Function-level nested types cannot conform to Equatable
//   https://bugs.swift.org/browse/SR-3092
private class TestItemViewModel: ElementViewModel, Identifiable, Equatable, CustomStringConvertible {
    var item: TestItem
    let tag: Int

    var element: TestItem { item }
    var id: Int64 { item.id }

    init(item: TestItem, tag: Int) {
        self.item = item
        self.tag = tag
    }
    
    var description: String {
        "ItemViewModel(\(item) tag=\(tag))"
    }
    
    static func == (lhs: TestItemViewModel, rhs: TestItemViewModel) -> Bool {
        return lhs.item == rhs.item && lhs.tag == rhs.tag
    }
}

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

        func item(_ id: Int64, _ name: String, _ tag: Int) -> TestItemViewModel {
            return TestItemViewModel(item: TestItem(id: id, name: name), tag: tag)
        }

        class TestViewModel {
            var expectation: XCTestExpectation!

            init() {
                self.reset()
            }

            func reset() {
                expectation = XCTestExpectation(description: "Items updated")
            }

            var itemViewModels: [TestItemViewModel] = [] {
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

        func verify(_ expectedItemViewModels: [TestItemViewModel], file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(vm.itemViewModels, expectedItemViewModels, file: file, line: line)
        }

        // Subscribe to the relation change publisher
        var tag = 0
        let cancellable = r
            .changes(TestItem.init)
            // TODO: Figure out better error handling approach for these publishers/subscribers
            .replaceError(with: RelationChangeSummary(added: [], updated: [], deleted: []))
            .reduce(to: \.itemViewModels, on: vm, orderBy: { $0.name <= $1.name }) { existingItemViewModel, item in
                // In this scenario, we reuse existing view model instances if provided; returning nil
                // here means "keep using the existing view model without reinserting"
                if let existing = existingItemViewModel {
                    existing.item = item
                    return nil
                } else {
                    tag += 1
                    return TestItemViewModel(item: item, tag: tag)
                }
            }
        XCTAssertNotNil(cancellable)
        
        verifySQLite(MakeRelation(
            ["id", "name"],
            [1,    "Alice"]
        ))

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

        // Rename a person (causing the ordering to change)
        reset()
        renamePerson(2, "Bon")
        await()
        verify([
            item(1, "Alice", 1),
            item(4, "Bob", 4),
            item(2, "Bon", 2),
            item(3, "Carlos", 3)
        ])

        verifySQLite(MakeRelation(
            ["id", "name"],
            [1,    "Alice"],
            [2,    "Bon"],
            [3,    "Carlos"],
            [4,    "Bob"]
        ))

        // Rename a person (without affecting order)
        reset()
        renamePerson(4, "Bobb")
        await()
        verify([
            item(1, "Alice", 1),
            item(4, "Bobb", 4),
            item(2, "Bon", 2),
            item(3, "Carlos", 3)
        ])

        verifySQLite(MakeRelation(
            ["id", "name"],
            [1,    "Alice"],
            [2,    "Bon"],
            [3,    "Carlos"],
            [4,    "Bobb"]
        ))
        
        // Delete a person
        reset()
        deletePerson(1)
        await()
        verify([
            item(4, "Bobb", 4),
            item(2, "Bon", 2),
            item(3, "Carlos", 3)
        ])

        verifySQLite(MakeRelation(
            ["id", "name"],
            [2,    "Bon"],
            [3,    "Carlos"],
            [4,    "Bobb"]
        ))

        // Perform multiple inserts/updates/deletes within a single transaction
        reset()
        deletePerson(2)
        addPerson(5, "Cate")
        renamePerson(4, "Bobby")
        await()
        verify([
            item(4, "Bobby", 4),
            item(3, "Carlos", 3),
            item(5, "Cate", 5)
        ])

        verifySQLite(MakeRelation(
            ["id", "name"],
            [3,    "Carlos"],
            [4,    "Bobby"],
            [5,    "Cate"]
        ))

        cancellable.cancel()
    }
}
