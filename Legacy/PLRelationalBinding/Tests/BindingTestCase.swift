//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import PLRelational
@testable import PLRelationalBinding

func AssertEqual(_ a: Relation?, _ b: Relation?, file: StaticString = #file, line: UInt = #line) {
    guard let a = a else {
        guard let b = b else { return }
        XCTAssertTrue(b.isEmpty.ok == true, "First relation is nil, second relation is not nil and not empty:\n\(b)", file: file, line: line)
        return
    }
    guard let b = b else {
        XCTAssertTrue(a.isEmpty.ok == true, "Second relation is nil, first relation is not nil and not empty:\n\(a)", file: file, line: line)
        return
    }
    XCTAssertEqual(a.scheme, b.scheme, "Relation schemes are not equal", file: file, line: line)
    let aRows = mapOk(a.rows(), { $0 })
    let bRows = mapOk(b.rows(), { $0 })
    
    switch (aRows, bRows) {
    case (.Ok(let aRows), .Ok(let bRows)):
        let aSet = Set(aRows)
        let bSet = Set(bRows)
        XCTAssertEqual(aRows.count, aSet.count, "Row generator returned duplicate values, all provided rows should be unique", file: file, line: line)
        XCTAssertEqual(bRows.count, bSet.count, "Row generator returned duplicate values, all provided rows should be unique")
        XCTAssertEqual(aSet, bSet, "Relations are not equal but should be. First relation:\n\(a)\n\nSecond relation:\n\(b)", file: file, line: line)
    default:
        XCTAssertNil(aRows.err, file: file, line: line)
        XCTAssertNil(bRows.err, file: file, line: line)
    }
}

func AssertEqual(_ a: AnyIterator<Result<Set<Row>, RelationError>>, _ b: Relation?, file: StaticString = #file, line: UInt = #line) {
    let result = mapOk(a, { $0 })
    guard let rows = result.ok?.joined() else {
        XCTFail("Got error iterating rows: \(String(describing: result.err))", file: file, line: line)
        return
    }
    
    if let first = rows.first {
        let scheme = Scheme(attributes: Set(first.attributes))
        let rowsSet = Set(rows)
        XCTAssertEqual(rows.count, rowsSet.count, "Row generator returned duplicate values, all provided rows should be unique")
        let relation = ConcreteRelation(scheme: scheme, values: rowsSet)
        AssertEqual(relation, b, file: file, line: line)
    } else {
        AssertEqual(nil, b, file: file, line: line)
    }
}

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
