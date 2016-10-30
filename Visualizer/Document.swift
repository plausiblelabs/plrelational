//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import libRelational

class Document: NSDocument {

    @IBOutlet var tableView: NSTableView!
    
    private var relTableView: RelationTableView!
    
    override init() {
        super.init()
    }

    override class func autosavesInPlace() -> Bool {
        return true
    }

    override var windowNibName: String? {
        return "Document"
    }

    override func data(ofType typeName: String) throws -> Data {
        throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: nil)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: nil)
    }
    
    override func windowControllerDidLoadNib(_ windowController: NSWindowController) {
        super.windowControllerDidLoadNib(windowController)
        
        let r = MakeRelation(
            ["id", "name"],
            [1,    "cat"],
            [2,    "dog"],
            [3,    "fish"])
        relTableView = RelationTableView(relation: r, orderAttr: "id", tableView: tableView)
    }
}
