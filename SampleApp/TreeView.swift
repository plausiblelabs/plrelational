//
//  TreeView.swift
//  Relational
//
//  Created by Chris Campbell on 5/9/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Cocoa
import libRelational

// TODO: This needs to be configurable, or at least made unique so that only internal drag-and-drop
// is allowed by default
private let PasteboardType = "coop.plausible.vp.pasteboard.TreeViewItem"

struct TreeViewModel {
    
    struct Data {
        let binding: OrderedTreeBinding
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
class TreeView: NSObject {
    
    private let outlineView: NSOutlineView
    private let model: TreeViewModel
    
    private var selectionObserverRemoval: (Void -> Void)?
    private var selfInitiatedSelectionChange = false
    
    init(outlineView: NSOutlineView, model: TreeViewModel) {
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

extension TreeView: NSOutlineViewDataSource {
    
    func outlineView(outlineView: NSOutlineView, numberOfChildrenOfItem item: AnyObject?) -> Int {
        switch item {
        case nil:
            return model.data.binding.nodes.count
        case let node as OrderedTreeBinding.Node:
            return node.children.count
        default:
            fatalError("Unexpected item type")
        }
    }
    
    func outlineView(outlineView: NSOutlineView, child index: Int, ofItem item: AnyObject?) -> AnyObject {
        switch item {
        case nil:
            return model.data.binding.nodes[index]
        case let node as OrderedTreeBinding.Node:
            return node.children[index]
        default:
            fatalError("Unexpected item type")
        }
    }
    
    func outlineView(outlineView: NSOutlineView, isItemExpandable item: AnyObject) -> Bool {
        let node = item as! OrderedTreeBinding.Node
        return node.children.count > 0
    }
    
    func outlineView(outlineView: NSOutlineView, pasteboardWriterForItem item: AnyObject) -> NSPasteboardWriting? {
        // TODO
        return nil
    }
    
    func outlineView(outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem: AnyObject?, proposedChildIndex proposedIndex: Int) -> NSDragOperation {
        // TODO
        return NSDragOperation.None
    }
    
    func outlineView(outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: AnyObject?, childIndex index: Int) -> Bool {
        // TODO
        return false
    }
}

extension TreeView: ExtOutlineViewDelegate {
    
    func outlineView(outlineView: NSOutlineView, viewForTableColumn: NSTableColumn?, item: AnyObject) -> NSView? {
        // TODO: Make this configurable
        let identifier = "PageCell"
        let node = item as! OrderedTreeBinding.Node
        let row = node.data
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
        // TODO
//        let itemID: RelationValue?
//        selfInitiatedSelectionChange = true
//        if outlineView.selectedRow >= 0 {
//            let row = model.data.binding.rows[outlineView.selectedRow].value
//            itemID = row[model.data.binding.idAttr]
//        } else {
//            itemID = nil
//        }
//        model.selection.set(id: itemID)
//        selfInitiatedSelectionChange = false
    }
}

extension TreeView {
    
    func selectionRelationChanged() {
        if selfInitiatedSelectionChange {
            return
        }

        // TODO
//        var index: Int?
//        if let selectedID = model.selection.get() {
//            if let selectedIndex = model.data.binding.indexForID(selectedID) {
//                index = selectedIndex
//            }
//        }
//        if let index = index {
//            outlineView.selectRowIndexes(NSIndexSet(index: index), byExtendingSelection: false)
//        } else {
//            outlineView.deselectAll(nil)
//        }
    }
}

extension TreeView: OrderedTreeBindingObserver {

    func onInsert(path: TreePath) {
        // TODO
//        let rows = NSIndexSet(index: index)
//        outlineView.insertItemsAtIndexes(rows, inParent: nil, withAnimation: [.EffectFade])
    }
    
    func onDelete(path: TreePath) {
        // TODO
//        let rows = NSIndexSet(index: index)
//        outlineView.removeItemsAtIndexes(rows, inParent: nil, withAnimation: [.EffectFade])
    }
    
    func onMove(srcPath srcPath: TreePath, dstPath: TreePath) {
        // TODO
//        outlineView.moveItemAtIndex(srcIndex, inParent: nil, toIndex: dstIndex, inParent: nil)
    }
}
