//
//  QueryRunnerTests.swift
//  Relational
//
//  Created by Mike Ash on 5/31/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import XCTest
@testable import libRelational

class QueryRunnerTests: XCTestCase {
    func testOneNode() {
        let r = MakeRelation(
            ["A"],
            ["one"])
        let planner = QueryPlanner(root: r)
        let runner = QueryRunner(nodeTree: planner.makeNodeTree())
        AssertEqual(runner.rows(), r)
    }
    
    func testUnion() {
        let r = MakeRelation(
            ["A"],
            ["one"])
        let s = MakeRelation(
            ["A"],
            ["two"])
        let union = r.union(s)
        let planner = QueryPlanner(root: union)
        let runner = QueryRunner(nodeTree: planner.makeNodeTree())
        AssertEqual(runner.rows(), MakeRelation(
            ["A"],
            ["one"],
            ["two"]))
    }
    
    func testIntersection() {
        let r = MakeRelation(
            ["A"],
            ["one"],
            ["three"])
        let s = MakeRelation(
            ["A"],
            ["two"],
            ["three"])
        let intersection = r.intersection(s)
        let planner = QueryPlanner(root: intersection)
        let runner = QueryRunner(nodeTree: planner.makeNodeTree())
        AssertEqual(runner.rows(), MakeRelation(
            ["A"],
            ["three"]))
    }
}
