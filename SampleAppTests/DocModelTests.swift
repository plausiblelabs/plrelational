//
//  DocModelTests.swift
//  Relational
//
//  Created by Chris Campbell on 5/15/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import XCTest
import libRelational
@testable import SampleApp

class DocModelTests: XCTestCase {
    
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
    
    func pretty(node: OrderedTreeBinding.Node, _ accum: String, _ indent: Int) -> String {
        var mutstr = accum
        let pad = Array(count: indent, repeatedValue: "  ").joinWithSeparator("")
        mutstr.appendContentsOf("\(pad)\(node.data["name"])\n")
        for child in node.children {
            mutstr = pretty(child, mutstr, indent + 1)
        }
        return mutstr
    }
    
    func prettyRoot(binding: OrderedTreeBinding) -> String {
        var s = ""
        for node in binding.root.children {
            s = pretty(node, s, 0)
        }
        return s
    }
    
    func testModel() {
        let model = DocModel(undoManager: UndoManager())
        
        func addCollection(name name: String, parentID: Int64?) {
            model.newCollection(name, type: .Page, parentID: parentID)
        }
        
        func verifyTree(binding: OrderedTreeBinding, _ expected: [String]) {
            let s = "\(expected.joinWithSeparator("\n"))\n"
            XCTAssertEqual(prettyRoot(binding), s)
        }
        
        // Insert some collections
        addCollection(name: "Group1", parentID: nil)
        addCollection(name: "Collection1", parentID: 1)
        addCollection(name: "Page1", parentID: 1)
        addCollection(name: "Page2", parentID: 1)
        addCollection(name: "Child1", parentID: 2)
        addCollection(name: "Child2", parentID: 2)
        addCollection(name: "Child3", parentID: 2)
        addCollection(name: "Group2", parentID: nil)
        verifyTree(model.docOutlineTreeViewModel.data.binding, [
            "Group1",
            "  Collection1",
            "    Child1",
            "    Child2",
            "    Child3",
            "  Page1",
            "  Page2",
            "Group2"
        ])
    }
}
