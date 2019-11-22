//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import PLRelational
@testable import PLRelationalBinding

class BindingTestCase: XCTestCase {
    
    var dbPaths: [String] = []
    
    override func tearDown() {
        for path in dbPaths {
            _ = try? FileManager.default.removeItem(atPath: path)
        }
    }
    
    func makeDB() -> (path: String, db: SQLiteDatabase) {
        let tmp = NSTemporaryDirectory() as NSString
        let dbname = "testing-\(UUID()).db"
        let path = tmp.appendingPathComponent(dbname)
        _ = try? FileManager.default.removeItem(atPath: path)
        
        let db = try! SQLiteDatabase(path)
        
        dbPaths.append(path)
        
        return (path, db)
    }

    func prettyArray(_ elements: [RowArrayElement]) -> [String] {
        var accum: [String] = []
        for element in elements {
            accum.append("\(element.data["name"])")
        }
        return accum
    }
    
    func verifyArray(_ array: ArrayProperty<RowArrayElement>, _ expected: [String], file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(prettyArray(array.elements), expected, file: file, line: line)
    }
    
    func pretty(_ node: RowTreeNode, _ accum: inout [String], _ indent: Int) {
        let pad = Array(repeating: "  ", count: indent).joined(separator: "")
        accum.append("\(pad)\(node.data["name"])")
        for child in node.children {
            pretty(child, &accum, indent + 1)
        }
    }
    
    func prettyRoot(_ tree: TreeProperty<RowTreeNode>) -> [String] {
        var accum: [String] = []
        for node in tree.root.children {
            pretty(node, &accum, 0)
        }
        return accum
    }
    
    func verifyTree(_ tree: TreeProperty<RowTreeNode>, _ expected: [String], file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(prettyRoot(tree), expected, file: file, line: line)
    }
    
    func path(_ tree: TreeProperty<RowTreeNode>, parentID: Int64?, index: Int) -> TreePath<RowTreeNode> {
        let parent = parentID.flatMap{ tree.nodeForID(RelationValue($0)) }
        return TreePath(parent: parent, index: index)
    }

    /// Synchronously waits for AsyncManager to process the given work and return to an `idle` state.
    func awaitCompletion(_ f: () -> Void) {
        f()
        awaitIdle()
    }
    
    /// Synchronously waits for AsyncManager to return to an `idle` state.
    func awaitIdle() {
        Async.awaitAsyncCompletion()
    }
}
