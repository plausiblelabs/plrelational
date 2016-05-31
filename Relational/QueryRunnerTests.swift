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
    
    func testDifference() {
        let r = MakeRelation(
            ["A"],
            ["one"],
            ["three"])
        let s = MakeRelation(
            ["A"],
            ["two"],
            ["three"])
        let difference = r.difference(s)
        let planner = QueryPlanner(root: difference)
        let runner = QueryRunner(nodeTree: planner.makeNodeTree())
        AssertEqual(runner.rows(), MakeRelation(
            ["A"],
            ["one"]))
    }
    
    func testProject() {
        let r = MakeRelation(
            ["A", "B"],
            ["1", "2"],
            ["1", "3"],
            ["2", "4"])
        let projected = r.project(["A"])
        let planner = QueryPlanner(root: projected)
        let runner = QueryRunner(nodeTree: planner.makeNodeTree())
        AssertEqual(runner.rows(), MakeRelation(
            ["A"],
            ["1"],
            ["2"]))
    }
    
    func testSelect() {
        let r = MakeRelation(
            ["A", "B"],
            ["1", "2"],
            ["1", "3"],
            ["2", "4"])
        let selected = r.select(Attribute("A") *== "1")
        let planner = QueryPlanner(root: selected)
        let runner = QueryRunner(nodeTree: planner.makeNodeTree())
        AssertEqual(runner.rows(), MakeRelation(
            ["A", "B"],
            ["1", "2"],
            ["1", "3"]))
    }
    
    func testJoin() {
        let a = MakeRelation(
            ["A", "B"],
            ["X", "1"],
            ["Y", "2"]
        )
        let b = MakeRelation(
            ["B", "C"],
            ["1", "T"],
            ["3", "V"]
        )
        
        let joined = a.join(b)
        let planner = QueryPlanner(root: joined)
        let runner = QueryRunner(nodeTree: planner.makeNodeTree())
        AssertEqual(runner.rows(), MakeRelation(
            ["A", "B", "C"],
            ["X", "1", "T"]))
    }
    
    func testRename() {
        let r = MakeRelation(
            ["A", "B"],
            ["1", "2"],
            ["1", "3"],
            ["2", "4"])
        let renamed = r.renameAttributes(["A": "ayy"])
        let planner = QueryPlanner(root: renamed)
        let runner = QueryRunner(nodeTree: planner.makeNodeTree())
        AssertEqual(runner.rows(), MakeRelation(
            ["ayy", "B"],
            ["1", "2"],
            ["1", "3"],
            ["2", "4"]))
    }
    
    func testUpdate() {
        let r = MakeRelation(
            ["A", "B"],
            ["1", "2"],
            ["1", "3"],
            ["2", "4"])
        let updated = r.withUpdate(["B": "5"])
        let planner = QueryPlanner(root: updated)
        let runner = QueryRunner(nodeTree: planner.makeNodeTree())
        AssertEqual(runner.rows(), MakeRelation(
            ["A", "B"],
            ["1", "5"],
            ["2", "5"]))
    }
    
    func testAggregate() {
        let r = MakeRelation(
            ["A", "B"],
            ["1", "2"],
            ["1", "3"],
            ["2", "4"])
        let updated = r.count()
        let planner = QueryPlanner(root: updated)
        let runner = QueryRunner(nodeTree: planner.makeNodeTree())
        AssertEqual(runner.rows(), MakeRelation(
            ["count"],
            [3]))
    }
}
