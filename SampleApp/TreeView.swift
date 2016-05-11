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
        let allowsChildren: (Row) -> Bool
        let contextMenu: (Row) -> ContextMenu?
        // Note: dstPath.index is relative to the state of the array *before* the item is removed.
        let move: (srcPath: TreePath, dstPath: TreePath) -> Void
    }
    
    struct Selection {
        let relation: ChangeLoggingRelation<SQLiteTableRelation>
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
        selectionObserverRemoval = model.selection.relation.addChangeObserver({ [weak self] _ in self?.selectionRelationChanged() })
        
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
            return model.data.binding.root.children.count
        case let node as OrderedTreeBinding.Node:
            return node.children.count
        default:
            fatalError("Unexpected item type")
        }
    }
    
    func outlineView(outlineView: NSOutlineView, child index: Int, ofItem item: AnyObject?) -> AnyObject {
        switch item {
        case nil:
            return model.data.binding.root.children[index]
        case let node as OrderedTreeBinding.Node:
            return node.children[index]
        default:
            fatalError("Unexpected item type")
        }
    }
    
    func outlineView(outlineView: NSOutlineView, isItemExpandable item: AnyObject) -> Bool {
        let node = item as! OrderedTreeBinding.Node
        return model.data.allowsChildren(node.data) && node.children.count > 0
    }
    
    func outlineView(outlineView: NSOutlineView, pasteboardWriterForItem item: AnyObject) -> NSPasteboardWriting? {
        let node = item as! OrderedTreeBinding.Node
        let row = node.data
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
            let currentParent = model.data.binding.parentForID(rowID)
            let proposedParent = proposedItem as? OrderedTreeBinding.Node
            if proposedParent === currentParent {
                // We are reordering the node within its existing parent (or at the top level)
                if let srcIndex = model.data.binding.indexForID(rowID) {
                    if proposedIndex >= 0 && proposedIndex != srcIndex && proposedIndex != srcIndex + 1 {
                        return .Move
                    }
                }
            } else {
                if let proposedParent = proposedParent {
                    // We are reparenting the item.  Note that we only allow dragging onto an existing node (i.e.,
                    // when proposedIndex < 0) for the case where the node is empty, since Cocoa doesn't propose
                    // a specific insertion index for that case.
                    if let currentNode = model.data.binding.nodeForID(rowID) {
                        if model.data.allowsChildren(proposedParent.data) &&
                            (proposedIndex >= 0 || proposedParent.children.isEmpty) &&
                            !model.data.binding.isNodeDescendent(proposedParent, ofAncestor: currentNode)
                        {
                            return .Move
                        }
                    }
                } else {
                    // We are dragging the node into the top level
                    if proposedIndex >= 0 {
                        return .Move
                    }
                }
            }
        }
        
        return .None
    }
    
    func outlineView(outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: AnyObject?, childIndex index: Int) -> Bool {
        let pboard = info.draggingPasteboard()
        if let rowIDString = pboard.stringForType(PasteboardType) {
            let rowID = RelationValue(Int64(rowIDString)!)
            
            let currentParent = model.data.binding.parentForID(rowID)
            let proposedParent = item as? OrderedTreeBinding.Node

            // Determine the destination index of the node relative to its new parent
            let srcIndex = model.data.binding.indexForID(rowID)!
            let dstIndex: Int
            if proposedParent === currentParent {
                // The node is being reordered within its existing parent
                dstIndex = index < srcIndex ? index : index - 1
            } else {
                // The node is being dragged onto or inside another node; note that index will
                // be -1 in the case where it is being dragged onto another node, but we will
                // account for that in OrderedTreeBinding.move()
                dstIndex = index
            }

            let srcPath = TreePath(parent: currentParent, index: srcIndex)
            let dstPath = TreePath(parent: proposedParent, index: dstIndex)
            model.data.move(srcPath: srcPath, dstPath: dstPath)
            return true
        }
        
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
        let node = item as! OrderedTreeBinding.Node
        return model.data.contextMenu(node.data).map{$0.nsmenu}
    }
    
    func outlineView(outlineView: NSOutlineView, shouldSelectItem item: AnyObject) -> Bool {
        return true
    }
    
    func outlineViewSelectionDidChange(notification: NSNotification) {
        if selfInitiatedSelectionChange {
            return
        }
        
        let itemID: RelationValue?
        selfInitiatedSelectionChange = true
        if outlineView.selectedRow >= 0 {
            let node = outlineView.itemAtRow(outlineView.selectedRow)! as! OrderedTreeBinding.Node
            let row = node.data
            itemID = row[model.data.binding.idAttr]
        } else {
            itemID = nil
        }
        model.selection.set(id: itemID)
        selfInitiatedSelectionChange = false
    }
}

extension TreeView {
    
    func selectionRelationChanged() {
        if selfInitiatedSelectionChange {
            return
        }

        var index: Int?
        if let selectedID = model.selection.get() {
            if let selectedNode = model.data.binding.nodeForID(selectedID) {
                // TODO: This is inefficient
                index = outlineView.rowForItem(selectedNode)
            }
        }
        selfInitiatedSelectionChange = true
        if let index = index {
            outlineView.selectRowIndexes(NSIndexSet(index: index), byExtendingSelection: false)
        } else {
            outlineView.deselectAll(nil)
        }
        selfInitiatedSelectionChange = false
    }
}

extension TreeView: OrderedTreeBindingObserver {

    func onInsert(path: TreePath) {
        let rows = NSIndexSet(index: path.index)
        outlineView.insertItemsAtIndexes(rows, inParent: path.parent, withAnimation: [.EffectFade])
    }
    
    func onDelete(path: TreePath) {
        let rows = NSIndexSet(index: path.index)
        outlineView.removeItemsAtIndexes(rows, inParent: path.parent, withAnimation: [.EffectFade])
    }
    
    func onMove(srcPath srcPath: TreePath, dstPath: TreePath) {
        outlineView.beginUpdates()
        
        outlineView.moveItemAtIndex(srcPath.index, inParent: srcPath.parent, toIndex: dstPath.index, inParent: dstPath.parent)

        // XXX: NSOutlineView doesn't appear to hide/show the disclosure triangle in the case where
        // the parent's emptiness is changing, so we have to do that manually
        if let srcParent = srcPath.parent {
            if srcParent.children.count == 0 {
                outlineView.reloadItem(srcParent)
            }
        }
        if let dstParent = dstPath.parent {
            if dstParent.children.count == 1 {
                outlineView.reloadItem(dstParent)
                outlineView.expandItem(dstParent)
            }
        }
        
        outlineView.endUpdates()
    }
}
