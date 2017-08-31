//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelationalBinding

public struct ListViewModel<E: ArrayElement> {
    public let data: ArrayProperty<E>
    public let contextMenu: ((E.Data) -> ContextMenu?)?
    // Note: dstIndex is relative to the state of the array *before* the item is removed.
    public let move: ((_ srcIndex: Int, _ dstIndex: Int) -> Void)?
    public let cellIdentifier: (E.Data) -> String

    public init(
        data: ArrayProperty<E>,
        contextMenu: ((E.Data) -> ContextMenu?)?,
        move: ((_ srcIndex: Int, _ dstIndex: Int) -> Void)?,
        cellIdentifier: @escaping (E.Data) -> String)
    {
        self.data = data
        self.contextMenu = contextMenu
        self.move = move
        self.cellIdentifier = cellIdentifier
    }
}

// Note: Normally this would be an NSView subclass, but for the sake of expedience we defined the UI in
// a single Document.xib, so this class simply manages a subset of views defined in that xib.
open class ListView<E: ArrayElement>: NSObject, NSOutlineViewDataSource, ExtOutlineViewDelegate {

    public let model: ListViewModel<E>
    private let outlineView: NSOutlineView

    /// Private pasteboard type that limits drag and drop to this specific outline view.
    private let pasteboardType: String

    private var elements: [E] {
        return model.data.elements
    }
    
    public lazy var selection: ExternalValueProperty<Set<E.ID>> = ExternalValueProperty(
        get: { [unowned self] in
            var itemIDs: [E.ID] = []
            for index in self.outlineView.selectedRowIndexes {
                if let element = self.elements[safe: index] {
                    itemIDs.append(element.id)
                }
            }
            return Set(itemIDs)
        },
        set: { [unowned self] selectedIDs, _ in
            let indexes = NSMutableIndexSet()
            for id in selectedIDs {
                if let index = self.model.data.indexForID(id) {
                    indexes.add(index)
                }
            }
            self.outlineView.selectRowIndexes(indexes as IndexSet, byExtendingSelection: false)
        }
    )

    public var configureCell: ((NSTableCellView, E.Data) -> Void)?
    
    private var arrayObserverRemoval: ObserverRemoval?
    //private var selfInitiatedSelectionChange = false
    
    /// Whether to animate insert/delete changes with a fade.
    public var animateChanges = false

    /// Whether to reload cell contents when the corresponding array element is updated.
    public var reloadCellOnUpdate = false
    
    /// Whether to select and enter edit mode for the cell that is inserted next.  This flag will
    /// be unset automatically after the cell is selected/edited.
    public var selectAndEditNextInsertedCell = false
    
    public init(model: ListViewModel<E>, outlineView: NSOutlineView) {
        self.model = model
        self.outlineView = outlineView
        self.pasteboardType = "PLBindableControls.ListView.pasteboard.\(ProcessInfo.processInfo.globallyUniqueString)"

        super.init()
        
        // TODO: Handle Begin/EndPossibleAsync events?
        arrayObserverRemoval = model.data.signal.observeValueChanging{ [weak self] changes, _ in
            self?.arrayChanged(changes)
        }
        
        outlineView.delegate = self
        outlineView.dataSource = self
        
        // Enable drag-and-drop
        outlineView.register(forDraggedTypes: [pasteboardType])
        outlineView.verticalMotionCanBeginDrag = true
        
        // Load the initial data
        model.data.start()
    }

    deinit {
        arrayObserverRemoval?()
    }

    // MARK: NSOutlineViewDataSource

    open func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        return elements.count
    }
    
    open func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        return elements[index]
    }
    
    open func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return false
    }
    
    open func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        if model.move == nil {
            return nil
        }
        
        let element = item as! E
        let pboardItem = NSPasteboardItem()
        pboardItem.setPropertyList(element.id.toPlist(), forType: pasteboardType)
        return pboardItem
    }
    
    open func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem: Any?, proposedChildIndex proposedIndex: Int) -> NSDragOperation {
        let pboard = info.draggingPasteboard()
        
        if let idPlist = pboard.propertyList(forType: pasteboardType) {
            let elementID = E.ID.fromPlist(idPlist as AnyObject)!
            if let srcIndex = model.data.indexForID(elementID) {
                if proposedIndex >= 0 && proposedIndex != srcIndex && proposedIndex != srcIndex + 1 {
                    return NSDragOperation.move
                }
            }
        }
        
        return NSDragOperation()
    }

    open func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        let pboard = info.draggingPasteboard()
        
        if let idPlist = pboard.propertyList(forType: pasteboardType), let move = model.move {
            let elementID = E.ID.fromPlist(idPlist as AnyObject)!
            if let srcIndex = model.data.indexForID(elementID) {
                move(srcIndex, index)
                return true
            }
        }
        
        return false
    }

    // MARK: ExtOutlineViewDelegate

    open func outlineView(_ outlineView: NSOutlineView, viewFor viewForTableColumn: NSTableColumn?, item: Any) -> NSView? {
        let element = item as! E
        let identifier = model.cellIdentifier(element.data)
        let view = outlineView.make(withIdentifier: identifier, owner: self) as! NSTableCellView
        configureCell?(view, element.data)
        return view
    }
    
    open func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        return false
    }
    
    open func outlineView(_ outlineView: NSOutlineView, menuForItem item: Any) -> NSMenu? {
        let element = item as! E
        return model.contextMenu?(element.data).map{$0.nsmenu}
    }
    
    open func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        return true
    }
    
    open func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        // TODO: Make this configurable
        return outlineView.make(withIdentifier: "RowView", owner: self) as? NSTableRowView
    }
    
    open func outlineViewSelectionDidChange(_ notification: Notification) {
        // TODO: Do we need this flag anymore?
//        if selfInitiatedSelectionChange {
//            return
//        }

//        selfInitiatedSelectionChange = true
        selection.changed(transient: false)
//        selfInitiatedSelectionChange = false
    }

    // MARK: Property observers

    private func arrayChanged(_ arrayChanges: [ArrayChange<E>]) {
        let animation: NSTableViewAnimationOptions = animateChanges ? [.effectFade] : []

        var rowToSelectAndEdit: Int?
        
        outlineView.beginUpdates()

        // Record changes that were made to the array relative to its previous state
        for change in arrayChanges {
            switch change {
            case .initial(_):
                outlineView.reloadData()
                
            case let .insert(index):
                let rows = IndexSet(integer: index)
                if selectAndEditNextInsertedCell {
                    rowToSelectAndEdit = index
                    selectAndEditNextInsertedCell = false
                }
                outlineView.insertItems(at: rows, inParent: nil, withAnimation: animation)
                
            case let .delete(index):
                let rows = IndexSet(integer: index)
                outlineView.removeItems(at: rows, inParent: nil, withAnimation: animation)
             
            case let .update(index):
                // XXX: There are cases where calling `reloadData` every time the array element's content is
                // updated may cause problems (like if there's a text field being edited), so for now we
                // make this opt-in with a flag
                if reloadCellOnUpdate {
                    let rows = IndexSet(integer: index)
                    outlineView.reloadData(forRowIndexes: rows, columnIndexes: [0])
                }
                
            case let .move(srcIndex, dstIndex):
                outlineView.moveItem(at: srcIndex, inParent: nil, to: dstIndex, inParent: nil)
                // XXX: If both the order and content of the array element are changed simultaneously, we'll
                // only see a `move` change here, and apparently `moveItem` doesn't cause the cell's contents
                // to be reloaded so we need to do that manually
                outlineView.reloadData(forRowIndexes: IndexSet(integer: dstIndex), columnIndexes: [0])
            }
        }

        // XXX: This prevents a call to selection.set(); we need to figure out a better way, so that
        // if the selection changes as a result of e.g. deleting an item, we update our selection
        // state, but do it in a way that doesn't go through the undo manager
        //selfInitiatedSelectionChange = true
        outlineView.endUpdates()
        //selfInitiatedSelectionChange = false
        
        if let row = rowToSelectAndEdit {
            // Select the newly inserted row
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            
            // Give focus to the text field in the newly inserted row
            if let rowView = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) {
                if let cellView = rowView as? NSTableCellView {
                    if let textField = cellView.textField {
                        if let window = cellView.window {
                            window.makeFirstResponder(textField)
                        }
                    }
                }
            }
        }
    }
}
