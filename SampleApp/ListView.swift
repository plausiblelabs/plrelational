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

    struct Data {
        let relation: Relation
        let idAttribute: Attribute
        let textAttribute: Attribute
    }
    
    struct Selection {
        let relation: SQLiteTableRelation
        let set: (id: Int64?) -> Void
        let index: () -> Int?
    }
    
    // XXX: This is basically a boxed version of the Row struct
    class RowData {
        let row: Row
        
        init(_ row: Row) {
            self.row = row
        }
    }
    
    private let outlineView: NSOutlineView
    private let data: Data
    private let selection: Selection
    private var rows: [RowData] = []

    private var dataObserverRemoval: (Void -> Void)?
    private var selectionObserverRemoval: (Void -> Void)?
    private var selfInitiatedSelectionChange = false
    
    init(outlineView: NSOutlineView, data: Data, selection: Selection) {
        self.outlineView = outlineView
        self.data = data
        self.selection = selection
        
        super.init()
        
        rows = data.relation.rows().map{RowData($0.ok!)}
        dataObserverRemoval = data.relation.addChangeObserver({ [weak self] in self?.dataRelationChanged() })

        selectionObserverRemoval = selection.relation.addChangeObserver({ [weak self] in self?.selectionRelationChanged() })
        
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
            // TODO: Make selection more direct
            let rowRelation = data.relation.select(rowData.row)
            textField.string = BidiBinding(relation: rowRelation, attribute: data.textAttribute, change: Change{ (newValue, oldValue, commit) in
                // TODO
                Swift.print("\(commit ? "COMMIT" : "CHANGE") new=\(newValue) old=\(oldValue)")
            })
        }
        return view
    }
    
    func outlineView(outlineView: NSOutlineView, isGroupItem item: AnyObject) -> Bool {
        return false
    }
    
    func outlineView(outlineView: NSOutlineView, menuForItem item: AnyObject) -> NSMenu? {
        return nil
    }
    
    func outlineView(outlineView: NSOutlineView, shouldSelectItem item: AnyObject) -> Bool {
        return true
    }
    
    func outlineViewSelectionDidChange(notification: NSNotification) {
        let itemID: Int64?
        selfInitiatedSelectionChange = true
        if outlineView.selectedRow >= 0 {
            let rowData = rows[outlineView.selectedRow]
            itemID = rowData.row[data.idAttribute].get()!
        } else {
            itemID = nil
        }
        selection.set(id: itemID)
        selfInitiatedSelectionChange = true
    }
}

extension ListView {
    
    func dataRelationChanged() {
        // TODO: Need fine-grained change observation
        rows = data.relation.rows().map{RowData($0.ok!)}
        outlineView.reloadData()
    }
    
    func selectionRelationChanged() {
        if selfInitiatedSelectionChange {
            return
        }
        
        if let index = selection.index() {
            outlineView.selectRowIndexes(NSIndexSet(index: index), byExtendingSelection: false)
        } else {
            outlineView.deselectAll(nil)
        }
    }
}
