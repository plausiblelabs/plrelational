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
    
    func testEquijoinOptimizationInfiniteLoop() {
        let r1 = InstrumentedSelectableRelation(scheme: ["n"], values: [["n": 1]])
        let r2 = InstrumentedSelectableRelation(scheme: ["n"], values: [["n": 1]])
        let r = r1.renameAttributes(["n": "m"]).join(r2.renameAttributes(["n": "m"]))
        AssertEqual(r, MakeRelation(["m"], [1]))
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
    
    func testSimpleMultipleEquijoinOptimization() {
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
        
        let toJoin1 = MakeRelation(["n"], [2])
        let toJoin2 = MakeRelation(["n"], [3])
        
        let joined1 = instrumented.join(toJoin1)
        let joined2 = instrumented.join(toJoin2)
        
        let final = joined1.union(joined2)
        AssertEqual(final, MakeRelation(["n"], [2], [3]))
        XCTAssertEqual(instrumented.rowsProvided, 2)
    }
    
    func testLessSimpleMultipleEquijoinOptimization() {
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
        let renamed = instrumented.renameAttributes(["n": "m"])
        
        let toJoin1 = MakeRelation(["m"], [2])
        let toJoin2 = MakeRelation(["m"], [3])
        
        let joined1 = renamed.join(toJoin1)
        let joined2 = renamed.join(toJoin2)
        
        let final = joined1.union(joined2)
        AssertEqual(final, MakeRelation(["m"], [2], [3]))
        XCTAssertEqual(instrumented.rowsProvided, 2)
    }
    
    func testEvenLessSimpleMultipleEquijoinOptimization() {
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
        let renamed = instrumented.renameAttributes(["n": "m"])
        let unioned = renamed.union(MakeRelation(["m"], [11]))
        
        let toJoin1 = MakeRelation(["m"], [2])
        let toJoin2 = MakeRelation(["m"], [3])
        
        let joined1 = unioned.join(toJoin1)
        let joined2 = unioned.join(toJoin2)
        
        let final = joined1.union(joined2)
        AssertEqual(final, MakeRelation(["m"], [2], [3]))
        XCTAssertEqual(instrumented.rowsProvided, 2)
    }
    
    func testMultipleEquijoinOptimization() {
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
        
        let toUnion = MakeRelation(["n"], [11])
        let toSubtract = MakeRelation(["n"], [1])
        
        let combined = instrumented.union(toUnion).difference(toSubtract)
        
        let toJoin1 = MakeRelation(["n"], [2])
        let toJoin2 = MakeRelation(["m"], [3])
        
        let joined1 = combined.join(toJoin1)
        let joined2 = combined.renameAttributes(["n": "m"]).join(toJoin2)
        
        let final = joined1.union(joined2.renameAttributes(["m": "n"]))
        AssertEqual(final, MakeRelation(["n"], [2], [3]))
        XCTAssertEqual(instrumented.rowsProvided, 2)
    }
    
    func testSelectOptimization() {
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
        
        let toUnion = MakeRelation(["n"], [11])
        let toSubtract = MakeRelation(["n"], [1])
        
        let combined = instrumented.union(toUnion).difference(toSubtract)
        
        let selected1 = combined.select(Attribute("n") *== 2)
        let selected2 = combined.select(Attribute("n") *== 3)
        
        let final = selected1.union(selected2)
        AssertEqual(final, MakeRelation(["n"], [2], [3]))
        XCTAssertEqual(instrumented.rowsProvided, 2)
    }
}

private class InstrumentedSelectableRelation: Relation {
    var scheme: Scheme
    
    var values: Set<Row>
    
    var debugName: String?
    
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
            let mapped = filtered.map({ row -> Result<Set<Row>, RelationError> in
                self.rowsProvided += 1
                return .Ok([row])
            })
            return AnyIterator(mapped.makeIterator())
        }, approximateCount: nil)
    }
    
    init(scheme: Scheme, values: Set<Row>) {
        self.scheme = scheme
        self.values = values
    }
}
