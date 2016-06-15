//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding

// TODO: This needs to be configurable, or at least made unique so that only internal drag-and-drop
// is allowed by default
private let PasteboardType = "coop.plausible.vp.pasteboard.TreeViewItem"

public struct TreeViewModel<N: TreeNode> {
    let data: ObservableTree<N>
    let allowsChildren: (N.Data) -> Bool
    let contextMenu: ((N.Data) -> ContextMenu?)?
    // Note: dstPath.index is relative to the state of the array *before* the item is removed.
    let move: ((srcPath: TreePath<N>, dstPath: TreePath<N>) -> Void)?
    let selection: MutableObservableValue<Set<N.ID>>
    let cellIdentifier: (N.Data) -> String
    let cellText: (N.Data) -> ObservableValue<String>
    let cellImage: ((N.Data) -> ObservableValue<Image>)?
    
    public init(
        data: ObservableTree<N>,
        allowsChildren: (N.Data) -> Bool,
        contextMenu: ((N.Data) -> ContextMenu?)?,
        move: ((srcPath: TreePath<N>, dstPath: TreePath<N>) -> Void)?,
        selection: MutableObservableValue<Set<N.ID>>,
        cellIdentifier: (N.Data) -> String,
        cellText: (N.Data) -> ObservableValue<String>,
        cellImage: ((N.Data) -> ObservableValue<Image>)?)
    {
        self.data = data
        self.allowsChildren = allowsChildren
        self.contextMenu = contextMenu
        self.move = move
        self.selection = selection
        self.cellIdentifier = cellIdentifier
        self.cellText = cellText
        self.cellImage = cellImage
    }
}

// Note: Normally this would be an NSView subclass, but for the sake of expedience we defined the UI in
// a single Document.xib, so this class simply manages a subset of views defined in that xib.
public class TreeView<N: TreeNode>: NSObject, NSOutlineViewDataSource, ExtOutlineViewDelegate {
    
    private let model: TreeViewModel<N>
    private let outlineView: NSOutlineView
    
    private var treeObserverRemoval: ObserverRemoval?
    private var selectionObserverRemoval: ObserverRemoval?
    private var selfInitiatedSelectionChange = false
    
    /// Whether to animate insert/delete changes with a fade.
    public var animateChanges = false
    
    /// Whether to automatically expand a parent when a child is inserted.
    public var autoExpand = false
    
    public init(model: TreeViewModel<N>, outlineView: NSOutlineView) {
        self.model = model
        self.outlineView = outlineView
        
        super.init()
        
        treeObserverRemoval = model.data.addChangeObserver({ [weak self] changes in self?.treeChanged(changes) })
        selectionObserverRemoval = model.selection.addChangeObserver({ [weak self] _ in self?.selectionChanged() })
        
        outlineView.setDelegate(self)
        outlineView.setDataSource(self)
        
        // Enable drag-and-drop
        outlineView.registerForDraggedTypes([PasteboardType])
        outlineView.verticalMotionCanBeginDrag = true
    }
    
    deinit {
        treeObserverRemoval?()
        selectionObserverRemoval?()
    }

    // MARK: NSOutlineViewDataSource

    public func outlineView(outlineView: NSOutlineView, numberOfChildrenOfItem item: AnyObject?) -> Int {
        switch item {
        case nil:
            return model.data.root.children.count
        case let node as N:
            return node.children.count
        default:
            fatalError("Unexpected item type")
        }
    }
    
    public func outlineView(outlineView: NSOutlineView, child index: Int, ofItem item: AnyObject?) -> AnyObject {
        switch item {
        case nil:
            return model.data.root.children[index]
        case let node as N:
            return node.children[index]
        default:
            fatalError("Unexpected item type")
        }
    }
    
    public func outlineView(outlineView: NSOutlineView, isItemExpandable item: AnyObject) -> Bool {
        let node = item as! N
        return model.allowsChildren(node.data) && node.children.count > 0
    }
    
    public func outlineView(outlineView: NSOutlineView, pasteboardWriterForItem item: AnyObject) -> NSPasteboardWriting? {
        if model.move == nil {
            return nil
        }
        
        let node = item as! N
        let pboardItem = NSPasteboardItem()
        pboardItem.setPropertyList(node.id.toPlist(), forType: PasteboardType)
        return pboardItem
    }
    
    public func outlineView(outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem: AnyObject?, proposedChildIndex proposedIndex: Int) -> NSDragOperation {
        let pboard = info.draggingPasteboard()
        
        if let idPlist = pboard.propertyListForType(PasteboardType) {
            let nodeID = N.ID.fromPlist(idPlist)!
            let currentParent = model.data.parentForID(nodeID)
            let proposedParent = proposedItem as? N
            if proposedParent === currentParent {
                // We are reordering the node within its existing parent (or at the top level)
                if let srcIndex = model.data.indexForID(nodeID) {
                    if proposedIndex >= 0 && proposedIndex != srcIndex && proposedIndex != srcIndex + 1 {
                        return .Move
                    }
                }
            } else {
                if let proposedParent = proposedParent {
                    // We are reparenting the item.  Note that we only allow dragging onto an existing node (i.e.,
                    // when proposedIndex < 0) for the case where the node is empty, since Cocoa doesn't propose
                    // a specific insertion index for that case.
                    if let currentNode = model.data.nodeForID(nodeID) {
                        if model.allowsChildren(proposedParent.data) &&
                            (proposedIndex >= 0 || proposedParent.children.isEmpty) &&
                            !model.data.isNodeDescendent(proposedParent, ofAncestor: currentNode)
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
    
    public func outlineView(outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: AnyObject?, childIndex index: Int) -> Bool {
        let pboard = info.draggingPasteboard()
        
        if let idPlist = pboard.propertyListForType(PasteboardType), move = model.move {
            let nodeID = N.ID.fromPlist(idPlist)!
            
            let currentParent = model.data.parentForID(nodeID)
            let proposedParent = item as? N

            // Note that `index` will be -1 in the case where it is being dragged onto
            // another node, but we will account for that in RelationObservableTree.move()
            let srcIndex = model.data.indexForID(nodeID)!
            let dstIndex = index

            let srcPath = TreePath(parent: currentParent, index: srcIndex)
            let dstPath = TreePath(parent: proposedParent, index: dstIndex)
            move(srcPath: srcPath, dstPath: dstPath)
            return true
        }
        
        return false
    }

    // MARK: ExtOutlineViewDelegate
    
    public func outlineView(outlineView: NSOutlineView, viewForTableColumn: NSTableColumn?, item: AnyObject) -> NSView? {
        let node = item as! N
        let identifier = model.cellIdentifier(node.data)
        let view = outlineView.makeViewWithIdentifier(identifier, owner: self) as! NSTableCellView
        if let textField = view.textField as? TextField {
            textField.string = model.cellText(node.data)
        }
        if let imageView = view.imageView as? ImageView {
            imageView.img = model.cellImage?(node.data)
        }
        return view
    }
    
    public func outlineView(outlineView: NSOutlineView, isGroupItem item: AnyObject) -> Bool {
        return false
    }
    
    public func outlineView(outlineView: NSOutlineView, menuForItem item: AnyObject) -> NSMenu? {
        let node = item as! N
        return model.contextMenu?(node.data).map{$0.nsmenu}
    }
    
    public func outlineView(outlineView: NSOutlineView, shouldSelectItem item: AnyObject) -> Bool {
        return true
    }
    
    public func outlineViewSelectionDidChange(notification: NSNotification) {
        if selfInitiatedSelectionChange {
            return
        }
        
        selfInitiatedSelectionChange = true
        
        var itemIDs: [N.ID] = []
        outlineView.selectedRowIndexes.enumerateIndexesUsingBlock { (index, stop) -> Void in
            if let node = self.outlineView.itemAtRow(index) as? N {
                itemIDs.append(node.id)
            }
        }
        model.selection.update(Set(itemIDs), ChangeMetadata(transient: false))
        
        selfInitiatedSelectionChange = false
    }

    // MARK: Observers

    private func selectionChanged() {
        if selfInitiatedSelectionChange {
            return
        }

        let indexes = NSMutableIndexSet()
        for id in model.selection.value {
            if let node = model.data.nodeForID(id) {
                // TODO: This is inefficient
                let index = outlineView.rowForItem(node)
                if index >= 0 {
                    indexes.addIndex(index)
                }
            }
        }
        
        selfInitiatedSelectionChange = true
        outlineView.selectRowIndexes(indexes, byExtendingSelection: false)
        selfInitiatedSelectionChange = false
    }
    
    private func treeChanged(changes: [TreeChange<N>]) {
        let animation: NSTableViewAnimationOptions = animateChanges ? [.EffectFade] : [.EffectNone]
        
        outlineView.beginUpdates()

        // TODO: Use a Set instead
        var itemsToReload: [N] = []
        var itemsToExpand: [N] = []
        
        for change in changes {
            switch change {
            case let .Insert(path):
                let rows = NSIndexSet(index: path.index)
                outlineView.insertItemsAtIndexes(rows, inParent: path.parent, withAnimation: animation)
                if let node = model.data.nodeAtPath(path) where autoExpand {
                    itemsToExpand.append(node)
                }

            case let .Delete(path):
                let rows = NSIndexSet(index: path.index)
                outlineView.removeItemsAtIndexes(rows, inParent: path.parent, withAnimation: animation)

            case let .Move(srcPath, dstPath):
                outlineView.moveItemAtIndex(srcPath.index, inParent: srcPath.parent, toIndex: dstPath.index, inParent: dstPath.parent)
                // XXX: NSOutlineView doesn't appear to hide/show the disclosure triangle in the case where
                // the parent's emptiness is changing, so we have to do that manually
                if let srcParent = srcPath.parent {
                    if srcParent.children.count == 0 {
                        itemsToReload.append(srcParent)
                    }
                }
                if let dstParent = dstPath.parent {
                    if dstParent.children.count == 1 {
                        itemsToReload.append(dstParent)
                        itemsToExpand.append(dstParent)
                    }
                }
            }
        }
        
        // Note: we need to wait until all insert/remove calls are processed above before
        // reloadItem() and/or expandItem() are called, otherwise NSOutlineView will get confused
        itemsToReload.forEach(outlineView.reloadItem)
        itemsToExpand.forEach(outlineView.expandItem)

        // XXX: This prevents a call to selection.set(); we need to figure out a better way, so that
        // if the selection changes as a result of e.g. deleting an item, we update our selection
        // state, but do it in a way that doesn't go through the undo manager
        selfInitiatedSelectionChange = true
        outlineView.endUpdates()
        selfInitiatedSelectionChange = false
    }
}
