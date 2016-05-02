//
//  ListView.swift
//  Relational
//
//  Created by Chris Campbell on 5/2/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Cocoa
import libRelational

// Note: Normally this would be an NSView subclass, but for the sake of expedience we defined the UI in
// a single Document.xib, so this class simply manages a subset of views defined in that xib.
class ListView: NSObject {

    // XXX: This is basically a boxed version of the Row struct
    class RowData {
        let row: Row
        
        init(_ row: Row) {
            self.row = row
        }
    }
    
    let outlineView: NSOutlineView
    let relation: Relation
    var rows: [RowData] = []

    var observerRemoval: (Void -> Void)?
    
    init(outlineView: NSOutlineView, relation: Relation) {
        self.outlineView = outlineView
        self.relation = relation
        
        super.init()
        
        rows = relation.rows().map{RowData($0.ok!)}
        observerRemoval = relation.addChangeObserver({ [weak self] in self?.relationChanged() })
        
        outlineView.setDelegate(self)
        outlineView.setDataSource(self)
    }
}

extension ListView: NSOutlineViewDataSource {
    
    func outlineView(outlineView: NSOutlineView, numberOfChildrenOfItem item: AnyObject?) -> Int {
        return rows.count
    }
    
    func outlineView(outlineView: NSOutlineView, child index: Int, ofItem item: AnyObject?) -> AnyObject {
        return rows[index]
    }
    
    func outlineView(outlineView: NSOutlineView, isItemExpandable item: AnyObject) -> Bool {
        return false
    }
}

extension ListView: ExtOutlineViewDelegate {
    
    func outlineView(outlineView: NSOutlineView, viewForTableColumn: NSTableColumn?, item: AnyObject) -> NSView? {
        // TODO: Make this configurable
        let identifier = "PageCell"
        let rowData = item as! RowData
        let view = outlineView.makeViewWithIdentifier(identifier, owner: self) as! NSTableCellView
        if let textField = view.textField as? TextField {
            // TODO: Set up bidirectional binding
            textField.stringValue = rowData.row["name"].get()!
        }
        return view
    }
    
    func outlineView(outlineView: NSOutlineView, isGroupItem item: AnyObject) -> Bool {
        return false
    }
    
    func outlineView(outlineView: NSOutlineView, menuForItem item: AnyObject) -> NSMenu? {
        return nil
    }
}

extension ListView {
    
    func relationChanged() {
        // TODO: Need fine-grained change observation
        rows = relation.rows().map{RowData($0.ok!)}
        outlineView.reloadData()
    }
}
