//
//  ListView.swift
//  Relational
//
//  Created by Chris Campbell on 5/2/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Cocoa
import libRelational

// TODO: This needs to be configurable, or at least made unique so that only internal drag-and-drop
// is allowed by default
private let PasteboardType = "coop.plausible.vp.pasteboard.ListViewItem"

struct ListViewModel {

    struct Data {
        let binding: OrderedBinding
        // Note: dstIndex is relative to the state of the array *before* the item is removed.
        let move: (srcIndex: Int, dstIndex: Int) -> Void
    }
    
    struct Selection {
        let relation: SQLiteTableRelation
        let set: (id: RelationValue?) -> Void
        let get: () -> RelationValue?
    }
    
    struct Cell {
        let text: StringBidiBinding
    }
    
    let data: Data
    let selection: Selection
    let cell: (Row) -> Cell
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
        
        model.data.binding.addObserver(self)
        selectionObserverRemoval = model.selection.relation.addChangeObserver({ [weak self] in self?.selectionRelationChanged() })
        
        outlineView.setDelegate(self)
        outlineView.setDataSource(self)
        
        // Enable drag-and-drop
        outlineView.registerForDraggedTypes([PasteboardType])
        outlineView.verticalMotionCanBeginDrag = true
    }
}

extension ListView: NSOutlineViewDataSource {
    
    func outlineView(outlineView: NSOutlineView, numberOfChildrenOfItem item: AnyObject?) -> Int {
        return model.data.binding.rows.count
    }
    
    func outlineView(outlineView: NSOutlineView, child index: Int, ofItem item: AnyObject?) -> AnyObject {
        return model.data.binding.rows[index]
    }
    
    func outlineView(outlineView: NSOutlineView, isItemExpandable item: AnyObject) -> Bool {
        return false
    }
    
    func outlineView(outlineView: NSOutlineView, pasteboardWriterForItem item: AnyObject) -> NSPasteboardWriting? {
        let row = (item as! Box<Row>).value
        // TODO: Don't assume Int64
        let rowID: Int64 = row[model.data.binding.idAttr].get()!
        let pboardItem = NSPasteboardItem()
        pboardItem.setString(String(rowID), forType: PasteboardType)
        return pboardItem
    }
    
    func outlineView(outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem: AnyObject?, proposedChildIndex proposedIndex: Int) -> NSDragOperation {
        let pboard = info.draggingPasteboard()
        if let rowIDString = pboard.stringForType(PasteboardType) {
            let rowID = RelationValue(Int64(rowIDString)!)
            if let srcIndex = model.data.binding.indexForID(rowID) {
                if proposedIndex >= 0 && proposedIndex != srcIndex && proposedIndex != srcIndex + 1 {
                    return NSDragOperation.Move
                }
            }
        }
        
        return NSDragOperation.None
    }
    
    func outlineView(outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: AnyObject?, childIndex index: Int) -> Bool {
        let pboard = info.draggingPasteboard()
        if let rowIDString = pboard.stringForType(PasteboardType) {
            let rowID = RelationValue(Int64(rowIDString)!)
            if let srcIndex = model.data.binding.indexForID(rowID) {
                model.data.move(srcIndex: srcIndex, dstIndex: index)
                return true
            }
        }
        
        return false
    }
}

extension ListView: ExtOutlineViewDelegate {
    
    func outlineView(outlineView: NSOutlineView, viewForTableColumn: NSTableColumn?, item: AnyObject) -> NSView? {
        // TODO: Make this configurable
        let identifier = "PageCell"
        let row = (item as! Box<Row>).value
        let view = outlineView.makeViewWithIdentifier(identifier, owner: self) as! NSTableCellView
        let cellModel = model.cell(row)
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
        let itemID: RelationValue?
        selfInitiatedSelectionChange = true
        if outlineView.selectedRow >= 0 {
            let row = model.data.binding.rows[outlineView.selectedRow].value
            itemID = row[model.data.binding.idAttr]
        } else {
            itemID = nil
        }
        model.selection.set(id: itemID)
        selfInitiatedSelectionChange = false
    }
}

extension ListView {
    
    func selectionRelationChanged() {
        if selfInitiatedSelectionChange {
            return
        }
        
        var index: Int?
        if let selectedID = model.selection.get() {
            if let selectedIndex = model.data.binding.indexForID(selectedID) {
                index = selectedIndex
            }
        }
        if let index = index {
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
