//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

@testable import PLRelational
import XCTest

class ChangeLoggingRelationTests: XCTestCase {
    func testExample() {
        let testRelation = LoggingTestRelation(scheme: ["n"])
        let r = ChangeLoggingRelation(baseRelation: testRelation)
        
        XCTAssertNil(r.add(["n": 1]).err)
        XCTAssertEqual(testRelation.adds, [])
        
        XCTAssertNil(r.save().err)
        XCTAssertEqual(testRelation.adds, [["n": 1]])
        
        testRelation.clearLog()
        
        XCTAssertNil(r.add(["n": 2]).err)
        XCTAssertEqual(testRelation.adds, [])
        
        XCTAssertNil(r.save().err)
        XCTAssertEqual(testRelation.adds, [["n": 2]])
    }
}

private class LoggingTestRelation: MutableRelation, RelationDefaultChangeObserverImplementation {
    let table: MemoryTableRelation
    
    var changeObserverData = RelationDefaultChangeObserverImplementationData()
    
    var adds: [Row] = []
    var deletes: [SelectExpression] = []
    var updates: [(SelectExpression, Row)] = []
    
    init(scheme: Scheme) {
        table = MemoryTableRelation(scheme: scheme)
    }
    
    func clearLog() {
        adds.removeAll()
        deletes.removeAll()
        updates.removeAll()
    }
    
    func add(_ row: Row) -> Result<Int64, RelationError> {
        adds.append(row)
        return table.add(row)
    }
    
    func delete(_ query: SelectExpression) -> Result<Void, RelationError> {
        deletes.append(query)
        return table.delete(query)
    }
    
    var scheme: Scheme {
        return table.scheme
    }
    
    var contentProvider: RelationContentProvider {
        return table.contentProvider
    }
    
    func contains(_ row: Row) -> Result<Bool, RelationError> {
        return table.contains(row)
    }
    
    func update(_ query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        updates.append((query, newValues))
        return table.update(query, newValues: newValues)
    }
}
