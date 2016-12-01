//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import PLRelational

class RelationRecursiveSelectTests: DBTestCase {
    
    func testRecursiveSelect() {
        
        class QueryResult {
            var names: [Int64: String] = [:]
            var values: [Int64: String] = [:]
            
            init() {
            }
        }
        
        let objects = MakeRelation(
            ["id", "name"],
            [1,    "one"],
            [2,    "two"],
            [3,    "three"],
            [4,    "four"],
            [5,    "five"]
        )
        let objectValues = MakeRelation(
            ["id", "value",  "referenced_names", "referenced_values"],
            [1,    "ONE",    "3 3", "2 3 3"],
            [2,    "TWO",    "3 4", "3"],
            [3,    "THREE",  "4",   "4"],
            [4,    "FOUR",   "5",   ""],
            [5,    "FIVE",   "",    ""]
        )
        
        let group = DispatchGroup()
        group.enter()

        var queryResult: QueryResult?
        var fetchedObjectRowIDs: [Int64] = []
        var fetchedObjectValueRowIDs: [Int64] = []
        
        func idsForReferenced(_ attr: Attribute, in row: Row) -> [RelationValue] {
            let refdIDsString: String = row[attr].get()!
            return refdIDsString
                .characters
                .split{ $0 == " " }
                .map{ RelationValue(Int64(String($0))!) }
        }
        
        func queriesForIDs(_ relation: RelationObject, _ attr: Attribute, _ values: [RelationValue]) -> [RecursiveQuery] {
            return values.map{ RecursiveQuery(relation: relation, attr: attr, value: $0) }
        }
        
        objectValues.recursiveSelect(
            initialQueryAttr: "id",
            initialQueryValue: 1,
            initialValue: QueryResult(),
            rowCallback: { (relation, row, accum) -> Result<(QueryResult, [RecursiveQuery]), RelationError> in
                let queries: [RecursiveQuery]
                let rowID: Int64 = row["id"].get()!
                if relation === objects {
                    let name: String = row["name"].get()!
                    accum.names[rowID] = name
                    queries = []
                    fetchedObjectRowIDs.append(rowID)
                } else if relation === objectValues {
                    let value: String = row["value"].get()!
                    accum.values[rowID] = value
                    let nameIDs = idsForReferenced("referenced_names", in: row)
                    let valueIDs = idsForReferenced("referenced_values", in: row)
                    let nameQueries = queriesForIDs(objects, "id", nameIDs)
                    let valueQueries = queriesForIDs(objectValues, "id", valueIDs)
                    queries = nameQueries + valueQueries
                    fetchedObjectValueRowIDs.append(rowID)
                } else {
                    queries = []
                }
                let result: (QueryResult, [RecursiveQuery]) = (accum, queries)
                return .Ok(result)
            },
            filterCallback: { accum, queries in
                // Filter out queries for those cases where we've already fetched the value
                var validQueries: Set<RecursiveQuery> = []
                for query in queries {
                    let rowID: Int64 = query.value.get()!
                    if query.relation === objects {
                        if accum.names[rowID] == nil {
                            validQueries.insert(query)
                        }
                    } else if query.relation === objectValues {
                        if accum.values[rowID] == nil {
                            validQueries.insert(query)
                        }
                    }
                }
                return validQueries
            },
            completionCallback: { result in
                XCTAssertNil(result.err)
                queryResult = result.ok!
                group.leave()
            }
        )
        
        let runloop = CFRunLoopGetCurrent()!
        group.notify(queue: DispatchQueue.global(), execute: { runloop.async({ CFRunLoopStop(runloop) }) })
        CFRunLoopRun()

        XCTAssertEqual(
            queryResult!.names,
            [
                3: "three",
                4: "four",
                5: "five"
            ]
        )
        XCTAssertEqual(
            queryResult!.values,
            [
                1: "ONE",
                2: "TWO",
                3: "THREE",
                4: "FOUR"
            ]
        )
        
        // Verify that no rows were fetched redundantly
        XCTAssertEqual(fetchedObjectRowIDs.sorted(), [3, 4, 5])
        XCTAssertEqual(fetchedObjectValueRowIDs.sorted(), [1, 2, 3, 4])
    }
}
