//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelational
import PLRelationalBinding

private let outlineRowHeight: CGFloat = 24.0
private let outlineSectionPadding: CGFloat = 12.0

public struct SectionedTreePath {
    public let parent: AnyObject?
    public let index: Int
    
    public init(parent: AnyObject?, index: Int) {
        self.parent = parent
        self.index = index
    }
}

extension SectionedTreePath: Equatable {}
public func ==(a: SectionedTreePath, b: SectionedTreePath) -> Bool {
    return a.parent === b.parent && a.index == b.index
}

public struct SectionedTreeSectionID {
    public let rawID: Int64
    
    public init(rawID: Int64) {
        self.rawID = rawID
    }
}

extension SectionedTreeSectionID: Equatable {}
public func ==(a: SectionedTreeSectionID, b: SectionedTreeSectionID) -> Bool {
    return a.rawID == b.rawID
}

public enum SectionedTreeChange { case
    initial(sectionID: SectionedTreeSectionID, path: SectionedTreePath?),
    insert(SectionedTreePath),
    delete(SectionedTreePath),
    move(src: SectionedTreePath, dst: SectionedTreePath)
}

extension SectionedTreeChange: Equatable {}
public func ==(a: SectionedTreeChange, b: SectionedTreeChange) -> Bool {
    switch (a, b) {
    case let (.initial(aid, apath), .initial(bid, bpath)): return aid == bid && apath == bpath
    case let (.insert(a), .insert(b)): return a == b
    case let (.delete(a), .delete(b)): return a == b
    case let (.move(asrc, adst), .move(bsrc, bdst)): return asrc == bsrc && adst == bdst
    default: return false
    }
}

public protocol SectionedTreeViewModelDelegate: class {
    func sectionedTreeViewModelTreeChanged(_ changes: [SectionedTreeChange])
}

public protocol SectionedTreeViewModel: class {
    associatedtype Path: Hashable
    
    weak var delegate: SectionedTreeViewModelDelegate? { get set }
    var selection: AsyncReadWriteProperty<Set<Path>> { get }
    var selectionExclusiveMode: Bool { get set }
    
    func start()
    
    func itemForPath(_ path: Path) -> Any?
    func pathForItem(_ item: Any?) -> Path?
    
    func childCountForItem(_ item: Any?) -> Int
    func child(index: Int, ofItem item: Any?) -> Any
    func isItemExpandable(_ item: Any) -> Bool
    func isItemSelectable(_ item: Any) -> Bool
    func isOutlineViewGroupStyle(_ item: Any) -> Bool
    func cellIdentifier(_ item: Any) -> String
    func cellText(_ item: Any) -> TextProperty?
    func cellImage(_ item: Any) -> ReadableProperty<Image>?

    func contextMenu(forItem item: Any) -> ContextMenu?

    /// Returns a plist-compatible object that identifies the given item to be moved by drag-and-drop, or nil if the
    /// item should not be draggable.
    func pasteboardPlistToMoveItem(_ item: Any) -> Any?
    
    /// Returns true if an item (identified by the given plist) can be dropped at the given location.
    func isDropAllowed(plist: Any, proposedItem item: Any?, proposedChildIndex childIndex: Int) -> Bool
    
    /// Finalizes the drag-and-drop operation for the given item and target location.
    func acceptDrop(plist: Any, item: Any?, childIndex: Int) -> Bool
}

open class SectionedTreeView<M: SectionedTreeViewModel> {

    private let impl: Impl<M>
    
    /// Whether to animate insert/delete changes with a fade.
    public var animateChanges: Bool {
        get { return impl.animateChanges }
        set { impl.animateChanges = newValue }
    }
    
    /// Whether to automatically expand a parent when a child is inserted.
    public var autoExpand: Bool {
        get { return impl.autoExpand }
        set { impl.autoExpand = newValue }
    }
    
    /// Allows for customization of row backgrounds.
    public var rowView: ((_ frame: NSRect, _ rowHeight: CGFloat) -> NSTableRowView)? {
        get { return impl.rowView }
        set { impl.rowView = newValue }
    }
    
    public init(model: M, outlineView: NSOutlineView) {
        self.impl = Impl(model: model, outlineView: outlineView)
    }
}

/// Private implementation for SectionedTreeView.
fileprivate class Impl<M: SectionedTreeViewModel>: NSObject, NSOutlineViewDataSource, ExtOutlineViewDelegate, SectionedTreeViewModelDelegate {

    private let model: M
    private let outlineView: NSOutlineView

    /// Private pasteboard type that limits drag and drop to this specific outline view.
    private let pasteboardType: NSPasteboard.PasteboardType
    
    private lazy var selection: MutableValueProperty<Set<M.Path>> = mutableValueProperty(Set(), { selectedPaths, _ in
        self.selectItems(selectedPaths)
    })
    
    fileprivate var animateChanges = false
    fileprivate var autoExpand = false
    fileprivate var rowView: ((_ frame: NSRect, _ rowHeight: CGFloat) -> NSTableRowView)?

    private var selfInitiatedSelectionChange = false
    
    init(model: M, outlineView: NSOutlineView) {
        self.model = model
        self.outlineView = outlineView
        self.pasteboardType = NSPasteboard.PasteboardType("PLBindableControls.SectionedTreeView.pasteboard.\(ProcessInfo.processInfo.globallyUniqueString)")

        super.init()
        
        self.model.delegate = self
        self.selection <~> model.selection
        
        outlineView.delegate = self
        outlineView.dataSource = self

        // Enable drag-and-drop
        outlineView.registerForDraggedTypes([pasteboardType])
        outlineView.verticalMotionCanBeginDrag = true

        model.start()
    }
    
    // MARK: NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        return model.childCountForItem(item)
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        return model.child(index: index, ofItem: item)
    }
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return model.isItemExpandable(item)
    }
    
    // MARK: ExtOutlineViewDelegate
    
    func outlineView(_ outlineView: NSOutlineView, viewFor viewForTableColumn: NSTableColumn?, item: Any) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier(model.cellIdentifier(item))
        let view = outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView
        if let textField = view?.textField as? TextField {
            let cellText = model.cellText(item)
            textField.bind(cellText)
        }
        if let imageView = view?.imageView as? ImageView {
            imageView.img.unbindAll()
            if let cellImage = model.cellImage(item) {
                imageView.img <~ cellImage
            }
        }
        return view
    }
    
    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        let identifier = NSUserInterfaceItemIdentifier("RowView")
        if let rowView = outlineView.makeView(withIdentifier: identifier, owner: self) {
            return rowView as? NSTableRowView
        } else {
            let rowView = self.rowView?(NSZeroRect, outlineRowHeight)
            rowView?.identifier = identifier
            return rowView
        }
    }
    
    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        return model.isOutlineViewGroupStyle(item)
    }
    
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        return model.isItemSelectable(item)
    }
    
    func outlineView(_ outlineView: NSOutlineView, menuForItem item: Any) -> NSMenu? {
        return model.contextMenu(forItem: item)?.nsmenu
    }
    
    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        var height = outlineRowHeight
        if outlineView.parent(forItem: item) == nil && !model.isOutlineViewGroupStyle(item) {
            // This is a top-level (non-section) item; add some extra padding at top
            height += outlineSectionPadding
        }
        return height
    }
    
    // MARK: Selection handling
    
    func outlineViewSelectionDidChange(_ notification: Notification) {
        if selfInitiatedSelectionChange {
            return
        }
        
        selfInitiatedSelectionChange = true
        selection.change(selectedItemPaths(), transient: false)
        selfInitiatedSelectionChange = false
    }
    
    /// Returns the set of item paths corresponding to the view's current selection state.
    private func selectedItemPaths() -> Set<M.Path> {
        var itemPaths: [M.Path] = []
        for index in self.outlineView.selectedRowIndexes {
            if let path = self.model.pathForItem(self.outlineView.item(atRow: index)) {
                itemPaths.append(path)
            }
        }
        return Set(itemPaths)
    }
    
    /// Selects the rows corresponding to the given set of item paths.
    private func selectItems(_ paths: Set<M.Path>) {
        // XXX: Ignore external selection changes made while in exclusive mode
        if model.selectionExclusiveMode {
            return
        }
        
        let indexes = NSMutableIndexSet()
        for path in paths {
            if let item = self.model.itemForPath(path) {
                // TODO: This is inefficient
                let index = self.outlineView.row(forItem: item)
                if index >= 0 {
                    indexes.add(index)
                }
            }
        }
        selfInitiatedSelectionChange = true
        self.outlineView.selectRowIndexes(indexes as IndexSet, byExtendingSelection: false)
        selfInitiatedSelectionChange = false
    }
    
    // MARK: Drag and drop
    
    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let plist = model.pasteboardPlistToMoveItem(item) else {
            return nil
        }
        
        let pboardItem = NSPasteboardItem()
        pboardItem.setPropertyList(plist, forType: pasteboardType)
        return pboardItem
    }
    
    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem: Any?, proposedChildIndex proposedIndex: Int) -> NSDragOperation {
        let pboard = info.draggingPasteboard()
        
        if let pathPlist = pboard.propertyList(forType: pasteboardType) {
            if model.isDropAllowed(plist: pathPlist, proposedItem: proposedItem, proposedChildIndex: proposedIndex) {
                return .move
            }
        }
        
        return NSDragOperation()
    }
    
    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        let pboard = info.draggingPasteboard()
        
        guard let pathPlist = pboard.propertyList(forType: pasteboardType) else {
            return false
        }
        
        return model.acceptDrop(plist: pathPlist, item: item, childIndex: index)
    }
    
    // MARK: SectionedTreeViewModelDelegate protocol
    
    func sectionedTreeViewModelTreeChanged(_ changes: [SectionedTreeChange]) {
        let animation: NSTableView.AnimationOptions = animateChanges ? [.effectFade] : []
        
        // Get the current set of IDs from the `selection` property and then use those to restore
        // the selection state after the changes are processed; this ensures that we select items
        // that were both inserted and marked for selection in a single (relational) transaction
        let itemsToSelect = selection.value
        
        outlineView.beginUpdates()
        
//        var itemsToReload: [AnyObject] = []
//        var itemsToExpand: [AnyObject] = []
        
        var autoExpandTopLevel = false
        
        for change in changes {
            switch change {
            case .initial:
                // TODO: Reload just this section
                outlineView.reloadData()
                if autoExpand {
                    autoExpandTopLevel = true
                }
                
            case .insert(let path):
                let rows = IndexSet(integer: path.index)
                outlineView.insertItems(at: rows, inParent: path.parent, withAnimation: animation)
//                if let item = model.itemForSectionedTreePath(path) where autoExpand {
//                    itemsToExpand.append(item)
//                }
                
            case .delete(let path):
                let rows = IndexSet(integer: path.index)
                outlineView.removeItems(at: rows, inParent: path.parent, withAnimation: animation)
                
            case .move(let srcPath, let dstPath):
                outlineView.moveItem(at: srcPath.index, inParent: srcPath.parent, to: dstPath.index, inParent: dstPath.parent)
                // XXX: NSOutlineView doesn't appear to hide/show the disclosure triangle in the case where
                // the parent's emptiness is changing, so we have to do that manually
//                if let srcParent = srcPath.parent {
//                    if srcParent.children.count == 0 {
//                        itemsToReload.append(srcParent)
//                    }
//                }
//                if let dstParent = dstPath.parent {
//                    if dstParent.children.count == 1 {
//                        itemsToReload.append(dstParent)
//                        itemsToExpand.append(dstParent)
//                    }
//                }
            }
        }
        
        // Note: we need to wait until all insert/remove calls are processed above before
        // reloadItem() and/or expandItem() are called, otherwise NSOutlineView will get confused
//        itemsToReload.forEach(outlineView.reloadItem)
//        itemsToExpand.forEach(outlineView.expandItem)
        
        // XXX: For now, let's auto-expand the initial top-level items
        if autoExpandTopLevel {
            outlineView.expandItem(nil, expandChildren: true)
        }
        
        selectItems(itemsToSelect)
        
        // TODO: We put a guard here as well so that no further selection changes are made when the
        // updates are committed
        selfInitiatedSelectionChange = true
        outlineView.endUpdates()
        selfInitiatedSelectionChange = false
    }
}

// XXX: This is a customized NSOutlineView implementation that fixes the way top-level nodes are indented when
// not using a section-style cell.
public class SectionedOutlineView: ExtOutlineView {
    
    /// Returns the most distant ancestor item for the given item.  Note that the returned item will be the same
    /// as the input item if it is a root item.
    func rootItemForItem(_ item: Any) -> Any {
        var rootItem = item
        while let parent = self.parent(forItem: rootItem) {
            rootItem = parent
        }
        return rootItem
    }
    
    /// Returns true if the item at the given row needs an extra level of indentation.
    func needsExtraIndentationAtRow(_ row: Int) -> Bool {
        // TODO: AnyObject requirement and comparison by reference are undesirable here
        if let item = self.item(atRow: row) as AnyObject? {
            let root = rootItemForItem(item) as AnyObject
            if root !== item {
                let isGroup = delegate!.outlineView!(self, isGroupItem: root)
                if !isGroup {
                    // Override the default indentation for the case where the most distant ancestor is not contained
                    // within a section (the default behavior for source list-style outline views does not indent
                    // the first level of items under a top-level collection)
                    return true
                }
            }
        }
        
        return false
    }
    
    public override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        var frame = super.frameOfCell(atColumn: column, row: row)
        if needsExtraIndentationAtRow(row) {
            frame.origin.x += indentationPerLevel
            frame.size.width -= indentationPerLevel
        }
        return frame
    }
    
    public override func frameOfOutlineCell(atRow row: Int) -> NSRect {
        var frame = super.frameOfOutlineCell(atRow: row)
        if needsExtraIndentationAtRow(row) {
            frame.origin.x += indentationPerLevel
        }
        if let item = item(atRow: row) {
            if parent(forItem: item) == nil && !delegate!.outlineView!(self, isGroupItem: item) {
                // This is a top-level collection; push the triangle down to account for the padding added elsewhere
                let cellFrame = frameOfCell(atColumn: 0, row: row)
                frame.origin.y = cellFrame.origin.y + outlineSectionPadding + ((outlineRowHeight - frame.height) / 2)
            }
        }
        return frame
    }
    
    public override func scrollRowToVisible(_ row: Int) {
        // XXX: When navigating the outline view with the keyboard up/down keys, NSOutlineView internals seem
        // to call this method which results in the item getting scrolled to the top with a clunky animation.
        // For now we'll do nothing here to avoid the default behavior.  If we ever need to be able to make
        // a specific row visible, we can revisit this and find a different solution.
    }
}
