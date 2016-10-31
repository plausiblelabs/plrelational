//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import libRelational

class Document: NSDocument {

    @IBOutlet var tableView1: NSTableView!
    @IBOutlet var tableView2: NSTableView!
    @IBOutlet var tableView3: NSTableView!
    
    private var relTableView1: RelationTableView!
    private var relTableView2: RelationTableView!
    private var relTableView3: RelationTableView!
    
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
        
        let employees = MakeRelation(
            ["emp_id", "emp_name", "dept_name"],
            [1, "Alice", "Sales"],
            [2, "Bob", "Finance"],
            [3, "Carlos", "Production"],
            [4, "Donald", "Production"])
        
        let departments = MakeRelation(
            ["dept_name", "manager_id"],
            ["Sales", 1],
            ["Production", 3])
        
        let joined = employees.leftOuterJoin(departments)

        relTableView1 = RelationTableView(
            relation: employees,
            orderAttr: "emp_id",
            orderedAttrs: ["emp_id", "emp_name", "dept_name"],
            tableView: tableView1)
        relTableView2 = RelationTableView(
            relation: departments,
            orderAttr: "dept_name",
            orderedAttrs: ["dept_name", "manager_id"],
            tableView: tableView2)
        relTableView3 = RelationTableView(
            relation: joined,
            orderAttr: "emp_id",
            orderedAttrs: ["emp_id", "emp_name", "dept_name", "manager_id"],
            tableView: tableView3)
    }
}
