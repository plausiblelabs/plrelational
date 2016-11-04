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
    public let data: TreeProperty<N>
    public let allowsChildren: (N.Data) -> Bool
    public let isSection: (N.Data) -> Bool
    public let contextMenu: ((N.Data) -> ContextMenu?)?
    // Note: dstPath.index is relative to the state of the array *before* the item is removed.
    public let move: ((_ srcPath: TreePath<N>, _ dstPath: TreePath<N>) -> Void)?
    public let selection: AsyncReadWriteProperty<Set<N.ID>>
    public let cellIdentifier: (N.Data) -> String
    public let cellText: (N.Data) -> TextProperty
    public let cellImage: ((N.Data) -> ReadableProperty<Image>?)?
    
    public init(
        data: TreeProperty<N>,
        allowsChildren: @escaping (N.Data) -> Bool,
        isSection: @escaping (N.Data) -> Bool,
        contextMenu: ((N.Data) -> ContextMenu?)?,
        move: ((_ srcPath: TreePath<N>, _ dstPath: TreePath<N>) -> Void)?,
        selection: AsyncReadWriteProperty<Set<N.ID>>,
        cellIdentifier: @escaping (N.Data) -> String,
        cellText: @escaping (N.Data) -> TextProperty,
        cellImage: ((N.Data) -> ReadableProperty<Image>?)?)
    {
        self.data = data
        self.isSection = isSection
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
open class TreeView<N: TreeNode>: NSObject, NSOutlineViewDataSource, ExtOutlineViewDelegate {
    
    private let model: TreeViewModel<N>
    private let outlineView: NSOutlineView
    
    private lazy var selection: MutableValueProperty<Set<N.ID>> = mutableValueProperty(Set(), { [unowned self] selectedIDs, _ in
        self.selectItems(selectedIDs)
    })

    private var treeObserverRemoval: ObserverRemoval?
    private var selfInitiatedSelectionChange = false
    
    /// Whether to animate insert/delete changes with a fade.
    open var animateChanges = false
    
    /// Whether to automatically expand a parent when a child is inserted.
    open var autoExpand = false
    
    public init(model: TreeViewModel<N>, outlineView: NSOutlineView) {
        self.model = model
        self.outlineView = outlineView
        
        super.init()
        
        // TODO: Handle will/didChange
        treeObserverRemoval = model.data.signal.observe(SignalObserver(
            valueWillChange: {},
            valueChanging: { [weak self] changes, _ in self?.treeChanged(changes) },
            valueDidChange: {}
        ))
        _ = selection <~> model.selection
        
        outlineView.delegate = self
        outlineView.dataSource = self
        
        // Enable drag-and-drop
        outlineView.register(forDraggedTypes: [PasteboardType])
        outlineView.verticalMotionCanBeginDrag = true
        
        // Load the initial data
        model.data.start()
    }
    
    deinit {
        treeObserverRemoval?()
    }

    // MARK: NSOutlineViewDataSource

    open func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        switch item {
        case nil:
            if let root = model.data.value {
                return root.children.count
            } else {
                return 0
            }
        case let node as N:
            return node.children.count
        default:
            fatalError("Unexpected item type")
        }
    }
    
    open func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        switch item {
        case nil:
            return model.data.value!.children[index]
        case let node as N:
            return node.children[index]
        default:
            fatalError("Unexpected item type")
        }
    }
    
    open func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        let node = item as! N
        return model.allowsChildren(node.data) && node.children.count > 0
    }
    
    open func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        if model.move == nil {
            return nil
        }
        
        let node = item as! N
        let pboardItem = NSPasteboardItem()
        pboardItem.setPropertyList(node.id.toPlist(), forType: PasteboardType)
        return pboardItem
    }
    
    open func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem: Any?, proposedChildIndex proposedIndex: Int) -> NSDragOperation {
        let pboard = info.draggingPasteboard()
        
        if let idPlist = pboard.propertyList(forType: PasteboardType) {
            let nodeID = N.ID.fromPlist(idPlist as AnyObject)!
            let currentParent = model.data.parentForID(nodeID)
            let proposedParent = proposedItem as? N
            if proposedParent === currentParent {
                // We are reordering the node within its existing parent (or at the top level)
                if let srcIndex = model.data.indexForID(nodeID) {
                    if proposedIndex >= 0 && proposedIndex != srcIndex && proposedIndex != srcIndex + 1 {
                        return .move
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
                            return .move
                        }
                    }
                } else {
                    // We are dragging the node into the top level
                    if proposedIndex >= 0 {
                        return .move
                    }
                }
            }
        }
        
        return NSDragOperation()
    }
    
    open func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        let pboard = info.draggingPasteboard()
        
        if let idPlist = pboard.propertyList(forType: PasteboardType), let move = model.move {
            let nodeID = N.ID.fromPlist(idPlist as AnyObject)!
            
            let currentParent = model.data.parentForID(nodeID)
            let proposedParent = item as? N

            // Note that `index` will be -1 in the case where it is being dragged onto
            // another node, but we will account for that in RelationTreeProperty.move()
            let srcIndex = model.data.indexForID(nodeID)!
            let dstIndex = index

            let srcPath = TreePath(parent: currentParent, index: srcIndex)
            let dstPath = TreePath(parent: proposedParent, index: dstIndex)
            move(srcPath, dstPath)
            return true
        }
        
        return false
    }

    // MARK: ExtOutlineViewDelegate
    
    open func outlineView(_ outlineView: NSOutlineView, viewFor viewForTableColumn: NSTableColumn?, item: Any) -> NSView? {
        let node = item as! N
        let identifier = model.cellIdentifier(node.data)
        let view = outlineView.make(withIdentifier: identifier, owner: self) as! NSTableCellView
        if let textField = view.textField as? TextField {
            let cellText = model.cellText(node.data)
            textField.bind(cellText)
        }
        if let imageView = view.imageView as? ImageView {
            imageView.img.unbindAll()
            if let image = model.cellImage?(node.data) {
                _ = imageView.img <~ image
            }
        }
        return view
    }
    
    open func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        let node = item as! N
        return model.isSection(node.data)
    }
    
    // TODO: This is one of those methods that incurs a performance penalty just by implementing it here,
    // but it's not needed by all TreeViews; we implement it just to allow for TreeView subclasses to
    // override it.  We should make a separate delegate class that can be overridden on an as needed basis.
    open func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        return outlineView.rowHeight
    }
    
    open func outlineView(_ outlineView: NSOutlineView, menuForItem item: Any) -> NSMenu? {
        let node = item as! N
        return model.contextMenu?(node.data).map{$0.nsmenu}
    }
    
    open func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        return true
    }
    
    open func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        // TODO: Make this configurable
        return outlineView.make(withIdentifier: "RowView", owner: self) as? NSTableRowView
    }
    
    open func outlineViewSelectionDidChange(_ notification: Notification) {
        if selfInitiatedSelectionChange {
            return
        }
        
        selfInitiatedSelectionChange = true
        selection.change(selectedItemIDs(), transient: false)
        selfInitiatedSelectionChange = false
    }
    
    /// Returns the set of node IDs corresponding to the view's current selection state.
    private func selectedItemIDs() -> Set<N.ID> {
        var itemIDs: [N.ID] = []
        for index in self.outlineView.selectedRowIndexes {
            if let node = self.outlineView.item(atRow: index) as? N {
                itemIDs.append(node.id)
            }
        }
        return Set(itemIDs)
    }
    
    /// Selects the rows corresponding to the given set of node IDs.
    private func selectItems(_ ids: Set<N.ID>) {
        let indexes = NSMutableIndexSet()
        for id in ids {
            if let node = self.model.data.nodeForID(id) {
                // TODO: This is inefficient
                let index = self.outlineView.row(forItem: node)
                if index >= 0 {
                    indexes.add(index)
                }
            }
        }
        selfInitiatedSelectionChange = true
        self.outlineView.selectRowIndexes(indexes as IndexSet, byExtendingSelection: false)
        selfInitiatedSelectionChange = false
    }

    // MARK: Property observers

    private func treeChanged(_ changes: [TreeChange<N>]) {
        let animation: NSTableViewAnimationOptions = animateChanges ? [.effectFade] : NSTableViewAnimationOptions()

        // Get the current set of IDs from the `selection` property and then use those to restore
        // the selection state after the changes are processed; this ensures that we select items
        // that were both inserted and marked for selection in a single (relational) transaction
        let itemsToSelect = selection.value
        
        outlineView.beginUpdates()

        // TODO: Use a Set instead
        var itemsToReload: [N] = []
        var itemsToExpand: [N] = []
        
        for change in changes {
            switch change {
            case .initial(_):
                outlineView.reloadData()

            case let .insert(path):
                let rows = IndexSet(integer: path.index)
                outlineView.insertItems(at: rows, inParent: path.parent, withAnimation: animation)
                if autoExpand, let node = model.data.nodeAtPath(path) {
                    itemsToExpand.append(node)
                }

            case let .delete(path):
                let rows = IndexSet(integer: path.index)
                outlineView.removeItems(at: rows, inParent: path.parent, withAnimation: animation)

            case let .move(srcPath, dstPath):
                outlineView.moveItem(at: srcPath.index, inParent: srcPath.parent, to: dstPath.index, inParent: dstPath.parent)
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

        selectItems(itemsToSelect)

        // TODO: We put a guard here as well so that no further selection changes are made when the
        // updates are committed
        selfInitiatedSelectionChange = true
        outlineView.endUpdates()
        selfInitiatedSelectionChange = false
    }
}
