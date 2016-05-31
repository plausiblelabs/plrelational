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
}
