//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import Combine
import PLRelational
@testable import PLRelationalCombine

class RelationChangePublisherTests: CombineTestCase {

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

        struct Person: Identifiable, Hashable, Equatable {
            let id: Int64
            let name: String

            init(id: Int64, name: String) {
                self.id = id
                self.name = name
            }

            init(row: Row) {
                self.init(id: row["id"].get()!, name: row["name"].get()!)
            }
        }

        func p(_ id: Int64, _ name: String) -> Person {
            Person(id: id, name: name)
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

        var expectation = XCTestExpectation(description: self.debugDescription)
        var summaries: [RelationChangeSummary<Person>] = []

        func reset() {
            expectation = XCTestExpectation(description: self.debugDescription)
            summaries = []
        }

        func await() {
            wait(for: [expectation], timeout: 5.0)
        }

        func verify(added: [Person], updated: [Person], deleted: [Person], file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(summaries.count, 1, file: file, line: line)
            let s = summaries[0]
            XCTAssertEqual(Set(s.added), Set(added), file: file, line: line)
            XCTAssertEqual(Set(s.updated), Set(updated), file: file, line: line)
            XCTAssertEqual(Set(s.deleted), Set(deleted), file: file, line: line)
        }

        // Subscribe to the relation change publisher
        let cancellable = r.changes(Person.init).sink(
            receiveCompletion: {
                XCTFail("No completion is expected, but we received \($0)")
            },
            receiveValue: { summary in
                summaries.append(summary)
                expectation.fulfill()
            }
        )
        XCTAssertNotNil(cancellable)

        verifySQLite(MakeRelation(
            ["id", "name"],
            [1,    "Alice"]
        ))

        // Verify that initial query produces Alice
        await()
        verify(added: [p(1, "Alice")], updated: [], deleted: [])

        // Insert some persons
        reset()
        addPerson(2, "Donald")
        await()
        verify(added: [p(2, "Donald")], updated: [], deleted: [])

        reset()
        addPerson(3, "Carlos")
        await()
        verify(added: [p(3, "Carlos")], updated: [], deleted: [])

        reset()
        addPerson(4, "Bob")
        await()
        verify(added: [p(4, "Bob")], updated: [], deleted: [])

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
        verify(added: [], updated: [p(2, "Bon")], deleted: [])

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
        verify(added: [], updated: [], deleted: [p(1, "Alice")])

        verifySQLite(MakeRelation(
            ["id", "name"],
            [2,    "Bon"],
            [3,    "Carlos"],
            [4,    "Bob"]
        ))

        // Perform multiple inserts/updates/deletes within a single transaction
        reset()
        deletePerson(2)
        addPerson(6, "Cate")
        renamePerson(4, "Bobby")
        addPerson(5, "Donna")
        await()
        verify(added: [p(5, "Donna"), p(6, "Cate")], updated: [p(4, "Bobby")], deleted: [p(2, "Bon")])

        verifySQLite(MakeRelation(
            ["id", "name"],
            [3,    "Carlos"],
            [4,    "Bobby"],
            [5,    "Donna"],
            [6,    "Cate"]
        ))

        cancellable.cancel()
    }
}
