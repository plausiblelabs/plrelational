//
//  AppTestCase.swift
//  Relational
//
//  Created by Chris Campbell on 5/18/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import XCTest
import libRelational
@testable import SampleApp

class AppTestCase: XCTestCase {
    
    func pretty(node: OrderedTreeBinding.Node, inout _ accum: [String], _ indent: Int) {
        let pad = Array(count: indent, repeatedValue: "  ").joinWithSeparator("")
        accum.append("\(pad)\(node.data["name"])")
        for child in node.children {
            pretty(child, &accum, indent + 1)
        }
    }
    
    func prettyRoot(binding: OrderedTreeBinding) -> [String] {
        var accum: [String] = []
        for node in binding.root.children {
            pretty(node, &accum, 0)
        }
        return accum
    }
    
    func verifyTree(binding: OrderedTreeBinding, _ expected: [String]) {
        XCTAssertEqual(prettyRoot(binding), expected)
    }
    
    func path(treeBinding: OrderedTreeBinding, parentID: Int64?, index: Int) -> TreePath {
        let parent = parentID.flatMap{ treeBinding.nodeForID(RelationValue($0)) }
        return TreePath(parent: parent, index: index)
    }
}
