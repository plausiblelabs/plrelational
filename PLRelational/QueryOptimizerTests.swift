//
//  QueryOptimizerTests.swift
//  PLRelational
//
//  Created by Mike Ash on 4/3/17.
//  Copyright © 2017 mikeash. All rights reserved.
//

import XCTest
import PLRelational

class QueryOptimizerTests: XCTestCase {
    func testEquijoinOptimization() {
        let instrumented = InstrumentedSelectableRelation(scheme: ["n"], values: [
            ["n": 1],
            ["n": 2],
            ["n": 3],
            ["n": 4],
            ["n": 5],
            ["n": 6],
            ["n": 7],
            ["n": 8],
            ["n": 9],
            ["n": 10],
        ])
        
        AssertEqual(instrumented, MakeRelation(["n"], [1], [2], [3], [4], [5], [6], [7], [8], [9], [10]))
        XCTAssertEqual(instrumented.rowsProvided, 10)
        instrumented.rowsProvided = 0
        
        AssertEqual(instrumented.join(MakeRelation(["n", "m"], [1, 2])), MakeRelation(["n", "m"], [1, 2]))
        XCTAssertEqual(instrumented.rowsProvided, 1)
        instrumented.rowsProvided = 0
    }
    
    func testEquijoinOptimizationWithRename() {
        let instrumented = InstrumentedSelectableRelation(scheme: ["n"], values: [
            ["n": 1],
            ["n": 2],
            ["n": 3],
            ["n": 4],
            ["n": 5],
            ["n": 6],
            ["n": 7],
            ["n": 8],
            ["n": 9],
            ["n": 10],
        ])
        
        AssertEqual(instrumented.renameAttributes(["n": "a"]).join(MakeRelation(["a", "b"], [1, 2])), MakeRelation(["a", "b"], [1, 2]))
        XCTAssertEqual(instrumented.rowsProvided, 1)
        instrumented.rowsProvided = 0
    }
}

private class InstrumentedSelectableRelation: Relation {
    var scheme: Scheme
    
    var values: Set<Row>
    
    var rowsProvided = 0
    
    func addChangeObserver(_ observer: RelationObserver, kinds: [RelationObservationKind]) -> ((Void) -> Void) {
        return {}
    }

    func update(_ query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        return .Ok()
    }

    func contains(_ row: Row) -> Result<Bool, RelationError> {
        return .Ok(values.contains(row))
    }

    var contentProvider: RelationContentProvider {
        return .efficientlySelectableGenerator({ expression in
            let filtered = self.values.lazy.filter({ expression.valueWithRow($0).boolValue })
            let mapped = filtered.map({ row -> Result<Row, RelationError> in
                self.rowsProvided += 1
                return .Ok(row)
            })
            return AnyIterator(mapped.makeIterator())
        })
    }
    
    init(scheme: Scheme, values: Set<Row>) {
        self.scheme = scheme
        self.values = values
    }
}
