//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
@testable import PLRelational

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
    
    func testJoinedJoinOptimization() {
        func makeR(size: Int) -> InstrumentedSelectableRelation {
            return InstrumentedSelectableRelation(scheme: ["n"], values: Set((0 ..< size).map({ ["n": RelationValue.integer(Int64($0))] })))
        }
        
        let small = makeR(size: 1)
        let medium = makeR(size: 10)
        let large = makeR(size: 100)
        
        // The naive method of running sources in order of their original size will run
        // small, medium, large. This will cause medium to iterate its whole content
        // because no select gets pushed down to it. A select does get pushed down
        // to large, so it really should go first. This test ensures that the system
        // notices this and runs small, large, medium, which is more efficient.
        let r = small.join(large).join(medium)
        AssertEqual(r, makeR(size: 1))
        XCTAssertEqual(small.rowsProvided, 1)
        XCTAssertEqual(medium.rowsProvided, 1)
        XCTAssertEqual(large.rowsProvided, 1)
    }
    
    func testJoinDerivativeOptimization() {
        let rm = InstrumentedSelectableRelation(scheme: ["m"], values: Set((1 ... 20).map({ ["m": $0] })))
            .setDebugName("rm")
        let rn = InstrumentedSelectableRelation(scheme: ["n"], values: Set((10 ... 30).map({ ["n": $0] })))
            .setDebugName("rn")
        let joined = rm.equijoin(rn, matching: ["m": "n"])
            .setDebugName("joined")
        
        let differentiator = RelationDifferentiator(relation: joined)
        let derivative = differentiator.computeDerivative()
        
        derivative.addChange(RelationChange(
            added: MakeRelation(["m"], [1], [10]),
            removed: MakeRelation(["m"], [0], [21])), toVariable: rm)
        
        derivative.addChange(RelationChange(
            added: MakeRelation(["n"], [20], [30]),
            removed: MakeRelation(["n"], [9], [31])), toVariable: rn)
        
        AssertEqual(derivative.change.added, MakeRelation(["m", "n"], [10, 10], [20, 20]))
        AssertEqual(derivative.change.removed, MakeRelation(["m", "n"], [9, 9], [21, 21]))
        
        XCTAssertEqual(rm.rowsProvided, 2)
        XCTAssertEqual(rn.rowsProvided, 2)
    }
    
    func testJoinedJoinWithOneRelationOptimization() {
        let instrumented = InstrumentedSelectableRelation(scheme: ["n"], values: Set((0 ..< 100).map({ ["n": $0] }))).setDebugName("instrumented")
        let tiny = MakeRelation(["n"], [1]).setDebugName("tiny")
        
        let selected = instrumented.select(Attribute("n") *< 10).setDebugName("selected")
        
        let j1 = tiny.join(selected).setDebugName("j1")
        let j2 = j1.join(instrumented).setDebugName("j2")
        
        j2.asyncAllRows({
            XCTAssertNil($0.err)
            XCTAssertEqual($0.ok, [["n": 1]])
            CFRunLoopStop(CFRunLoopGetCurrent())
            XCTAssertEqual(instrumented.rowsProvided, 11)
        })
        CFRunLoopRunOrFail()
        
        j2.asyncAllRows({
            XCTAssertNil($0.err)
            XCTAssertEqual($0.ok, [["n": 1]])
            CFRunLoopStop(CFRunLoopGetCurrent())
            XCTAssertEqual(instrumented.rowsProvided, 22)
        })
        CFRunLoopRunOrFail()
        
        j2.asyncAllRows({
            XCTAssertNil($0.err)
            XCTAssertEqual($0.ok, [["n": 1]])
            CFRunLoopStop(CFRunLoopGetCurrent())
            XCTAssertEqual(instrumented.rowsProvided, 33)
        })
        CFRunLoopRunOrFail()
    }
    
    func testCachedJoinedJoinWithOneRelationOptimization() {
        let instrumented = InstrumentedSelectableRelation(scheme: ["n"], values: Set((0 ..< 100).map({ ["n": $0] }))).setDebugName("instrumented")
        let tiny = MakeRelation(["n"], [1]).setDebugName("tiny")
        
        let selected = instrumented.select(Attribute("n") *< 10).setDebugName("selected")
        
        // TODO: eventually it would be nice if the direct version of the multiple join
        // would be fast on its own. For now, we need this cache to make it fast. When
        // we get to fixing the direct case, we can take the cache out.
        let cached = selected.cache(upTo: .max).setDebugName("cached")
        let j1 = tiny.join(cached).setDebugName("j1")
        let j2 = j1.join(instrumented).setDebugName("j2")
        
        j2.asyncAllRows({
            XCTAssertNil($0.err)
            XCTAssertEqual($0.ok, [["n": 1]])
            CFRunLoopStop(CFRunLoopGetCurrent())
            XCTAssertEqual(instrumented.rowsProvided, 11)
        })
        CFRunLoopRunOrFail()
        
        j2.asyncAllRows({
            XCTAssertNil($0.err)
            XCTAssertEqual($0.ok, [["n": 1]])
            CFRunLoopStop(CFRunLoopGetCurrent())
            XCTAssertEqual(instrumented.rowsProvided, 12)
        })
        CFRunLoopRunOrFail()
        
        j2.asyncAllRows({
            XCTAssertNil($0.err)
            XCTAssertEqual($0.ok, [["n": 1]])
            CFRunLoopStop(CFRunLoopGetCurrent())
            XCTAssertEqual(instrumented.rowsProvided, 13)
        })
        CFRunLoopRunOrFail()
    }
}

private class InstrumentedSelectableRelation: Relation {
    var scheme: Scheme
    
    var values: Set<Row>
    
    var debugName: String?
    
    var rowsProvided = 0
    
    func addChangeObserver(_ observer: RelationObserver, kinds: [RelationObservationKind]) -> (() -> Void) {
        return {}
    }

    func update(_ query: SelectExpression, newValues: Row) -> Result<Void, RelationError> {
        return .Ok()
    }

    func contains(_ row: Row) -> Result<Bool, RelationError> {
        return .Ok(values.contains(row))
    }

    private func filteredValues(_ expression: SelectExpression) -> [Row] {
        return values.filter({ expression.valueWithRow($0).boolValue })
    }
    
    var contentProvider: RelationContentProvider {
        return .efficientlySelectableGenerator({ expression in
            let filtered = self.filteredValues(expression)
            let mapped = filtered.map({ row -> Result<Set<Row>, RelationError> in
                self.rowsProvided += 1
                return .Ok([row])
            })
            return AnyIterator(mapped.makeIterator())
        }, approximateCount: {
            Double(self.filteredValues($0).count)
        })
    }
    
    init(scheme: Scheme, values: Set<Row>) {
        self.scheme = scheme
        self.values = values
    }
}
