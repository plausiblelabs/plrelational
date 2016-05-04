//
//  ListView.swift
//  Relational
//
//  Created by Chris Campbell on 5/2/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Cocoa
import libRelational

struct ListViewModel {
    
    struct Selection {
        let relation: SQLiteTableRelation
        let set: (id: Int64?) -> Void
        let index: () -> Int?
    }
    
    struct Cell {
        let text: BidiBinding<String>
    }
    
    let data: OrderedBinding
    let selection: Selection
    let cell: (Relation) -> Cell
}

// Note: Normally this would be an NSView subclass, but for the sake of expedience we defined the UI in
// a single Document.xib, so this class simply manages a subset of views defined in that xib.
class ListView: NSObject {

    private let outlineView: NSOutlineView
    private let model: ListViewModel

    private var selectionObserverRemoval: (Void -> Void)?
    private var selfInitiatedSelectionChange = false
    
    init(outlineView: NSOutlineView, model: ListViewModel) {
        self.outlineView = outlineView
        self.model = model
        
        super.init()
        
        model.data.addObserver(self)
        selectionObserverRemoval = model.selection.relation.addChangeObserver({ [weak self] in self?.selectionRelationChanged() })
        
        outlineView.setDelegate(self)
        outlineView.setDataSource(self)
    }
}

extension ListView: NSOutlineViewDataSource {
    
    func outlineView(outlineView: NSOutlineView, numberOfChildrenOfItem item: AnyObject?) -> Int {
        return model.data.rows.count
    }
    
    func outlineView(outlineView: NSOutlineView, child index: Int, ofItem item: AnyObject?) -> AnyObject {
        return model.data.rows[index]
    }
    
    func outlineView(outlineView: NSOutlineView, isItemExpandable item: AnyObject) -> Bool {
        return false
    }
}

extension ListView: ExtOutlineViewDelegate {
    
    func outlineView(outlineView: NSOutlineView, viewForTableColumn: NSTableColumn?, item: AnyObject) -> NSView? {
        // TODO: Make this configurable
        let identifier = "PageCell"
        let row = (item as! Box<Row>).value
        // TODO: Ideally OrderedBinding.relation would be private; need a better way to observe
        // a single value
        let rowRelation = model.data.relation.select(row)
        let view = outlineView.makeViewWithIdentifier(identifier, owner: self) as! NSTableCellView
        let cellModel = model.cell(rowRelation)
        if let textField = view.textField as? TextField {
            textField.string = cellModel.text
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
            let row = model.data.rows[outlineView.selectedRow].value
            itemID = row[model.data.idAttr].get()!
        } else {
            itemID = nil
        }
        model.selection.set(id: itemID)
        selfInitiatedSelectionChange = true
    }
}

extension ListView {
    
    func selectionRelationChanged() {
        if selfInitiatedSelectionChange {
            return
        }
        
        if let index = model.selection.index() {
            outlineView.selectRowIndexes(NSIndexSet(index: index), byExtendingSelection: false)
        } else {
            outlineView.deselectAll(nil)
        }
    }
}

extension ListView: OrderedBindingObserver {

    func onInsert(index: Int) {
        let rows = NSIndexSet(index: index)
        outlineView.insertItemsAtIndexes(rows, inParent: nil, withAnimation: [.EffectFade])
    }

    func onDelete(index: Int) {
        let rows = NSIndexSet(index: index)
        outlineView.removeItemsAtIndexes(rows, inParent: nil, withAnimation: [.EffectFade])
    }

    func onMove(srcIndex srcIndex: Int, dstIndex: Int) {
        outlineView.moveItemAtIndex(srcIndex, inParent: nil, toIndex: dstIndex, inParent: nil)
    }
}
