//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import Combine
import PLRelational
@testable import PLRelationalCombine

class RelationChangePublisherTests: CombineTestCase {

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

        var expectation = XCTestExpectation(description: self.debugDescription)
        var summaries: [RelationChangeSummary] = []
        
        func reset() {
            expectation = XCTestExpectation(description: self.debugDescription)
            summaries = []
        }
        
        func await() {
            wait(for: [expectation], timeout: 5.0)
        }
        
        func verify(added: [Row], updated: [Row], deleted: [Row]) {
            XCTAssertEqual(summaries.count, 1)
            let s = summaries[0]
            XCTAssertEqual(Set(s.added), Set(added))
            XCTAssertEqual(Set(s.updated), Set(updated))
            XCTAssertEqual(Set(s.deleted), Set(deleted))
        }
        
        // Subscribe to the relation change publisher
        let cancellable = r.changes().sink(
            receiveCompletion: { _ in
                XCTFail("No completion is expected")
            },
            receiveValue: { summary in
                summaries.append(summary)
                expectation.fulfill()
            }
        )
        XCTAssertNotNil(cancellable)

        // Verify that initial query produces Alice
        await()
        verify(added: [row(1, "Alice")], updated: [], deleted: [])

        // Insert some persons
        reset()
        addPerson(2, "Donald")
        await()
        verify(added: [row(2, "Donald")], updated: [], deleted: [])

        reset()
        addPerson(3, "Carlos")
        await()
        verify(added: [row(3, "Carlos")], updated: [], deleted: [])

        reset()
        addPerson(4, "Bob")
        await()
        verify(added: [row(4, "Bob")], updated: [], deleted: [])
        
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
        verify(added: [], updated: [row(2, "Bon")], deleted: [])

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
        verify(added: [], updated: [], deleted: [row(1, "Alice")])

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
        verify(added: [row(5, "Donna"), row(6, "Cate")], updated: [row(4, "Bobby")], deleted: [row(2, "Bon")])

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
