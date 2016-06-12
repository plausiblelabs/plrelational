//
//  BindingTestCase.swift
//  Relational
//
//  Created by Chris Campbell on 5/31/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import XCTest
import libRelational
@testable import Binding

class BindingTestCase: XCTestCase {
    
    var dbPaths: [String] = []
    
    override func tearDown() {
        for path in dbPaths {
            _ = try? NSFileManager.defaultManager().removeItemAtPath(path)
        }
    }
    
    func makeDB() -> (path: String, db: SQLiteDatabase) {
        let tmp = NSTemporaryDirectory() as NSString
        let dbname = "testing-\(NSUUID()).db"
        let path = tmp.stringByAppendingPathComponent(dbname)
        _ = try? NSFileManager.defaultManager().removeItemAtPath(path)
        
        let db = try! SQLiteDatabase(path)
        
        dbPaths.append(path)
        
        return (path, db)
    }
    
    func prettyArray(binding: RelationArrayBinding) -> [String] {
        var accum: [String] = []
        for element in binding.elements {
            accum.append("\(element.data["name"])")
        }
        return accum
    }
    
    func verifyArray(binding: RelationArrayBinding, _ expected: [String], file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(prettyArray(binding), expected, file: file, line: line)
    }
    
    func pretty(node: RowTreeNode, inout _ accum: [String], _ indent: Int) {
        let pad = Array(count: indent, repeatedValue: "  ").joinWithSeparator("")
        accum.append("\(pad)\(node.data["name"])")
        for child in node.children {
            pretty(child, &accum, indent + 1)
        }
    }
    
    func prettyRoot(tree: ObservableTree<RowTreeNode>) -> [String] {
        var accum: [String] = []
        for node in tree.root.children {
            pretty(node, &accum, 0)
        }
        return accum
    }
    
    func verifyTree(tree: ObservableTree<RowTreeNode>, _ expected: [String], file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(prettyRoot(tree), expected, file: file, line: line)
    }
    
    func path(tree: ObservableTree<RowTreeNode>, parentID: Int64?, index: Int) -> TreePath<RowTreeNode> {
        let parent = parentID.flatMap{ tree.nodeForID(RelationValue($0)) }
        return TreePath(parent: parent, index: index)
    }
}
