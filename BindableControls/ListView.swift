//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding

// TODO: This needs to be configurable, or at least made unique so that only internal drag-and-drop
// is allowed by default
private let PasteboardType = "coop.plausible.vp.pasteboard.ListViewItem"

public struct ListViewModel<E: ArrayElement> {
    public let data: ArrayProperty<E>
    public let contextMenu: ((E.Data) -> ContextMenu?)?
    // Note: dstIndex is relative to the state of the array *before* the item is removed.
    public let move: ((_ srcIndex: Int, _ dstIndex: Int) -> Void)?
    public let selection: AsyncReadWriteProperty<Set<E.ID>>?
    public let cellIdentifier: (E.Data) -> String
    public let cellText: (E.Data) -> CellTextProperty
    public let cellImage: ((E.Data) -> ReadableProperty<Image>)?

    public init(
        data: ArrayProperty<E>,
        contextMenu: ((E.Data) -> ContextMenu?)?,
        move: ((_ srcIndex: Int, _ dstIndex: Int) -> Void)?,
        selection: AsyncReadWriteProperty<Set<E.ID>>?,
        cellIdentifier: @escaping (E.Data) -> String,
        cellText: @escaping (E.Data) -> CellTextProperty,
        cellImage: ((E.Data) -> ReadableProperty<Image>)?)
    {
        self.data = data
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
open class ListView<E: ArrayElement>: NSObject, NSOutlineViewDataSource, ExtOutlineViewDelegate {

    open let model: ListViewModel<E>
    fileprivate let outlineView: NSOutlineView

    fileprivate var elements: [E] {
        return model.data.value ?? []
    }
    
    fileprivate lazy var selection: ExternalValueProperty<Set<E.ID>> = ExternalValueProperty(
        get: { [unowned self] in
            var itemIDs: [E.ID] = []
            for index in self.outlineView.selectedRowIndexes {
                if let element = self.outlineView.item(atRow: index) as? E {
                    itemIDs.append(element.id)
                }
            }
            return Set(itemIDs)
        },
        set: { [unowned self] selectedIDs, _ in
            let indexes = NSMutableIndexSet()
            for id in selectedIDs {
                if let element = self.model.data.elementForID(id, self.elements) {
                    // TODO: This is inefficient
                    let index = self.outlineView.row(forItem: element)
                    if index >= 0 {
                        indexes.add(index)
                    }
                }
            }
            self.outlineView.selectRowIndexes(indexes as IndexSet, byExtendingSelection: false)
        }
    )

    fileprivate var arrayObserverRemoval: ObserverRemoval?
    //private var selfInitiatedSelectionChange = false
    
    /// Whether to animate insert/delete changes with a fade.
    open var animateChanges = false

    public init(model: ListViewModel<E>, outlineView: NSOutlineView) {
        self.model = model
        self.outlineView = outlineView

        super.init()
        
        // TODO: Handle will/didChange
        arrayObserverRemoval = model.data.signal.observe(SignalObserver(
            valueWillChange: {},
            valueChanging: { [weak self] stateChange, _ in self?.arrayChanged(stateChange) },
            valueDidChange: {}
        ))
        if let selectionProp = model.selection {
            _ = selection <~> selectionProp
        }
        
        outlineView.delegate = self
        outlineView.dataSource = self
        
        // Enable drag-and-drop
        outlineView.register(forDraggedTypes: [PasteboardType])
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
        pboardItem.setPropertyList(element.id.toPlist(), forType: PasteboardType)
        return pboardItem
    }
    
    open func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem: Any?, proposedChildIndex proposedIndex: Int) -> NSDragOperation {
        let pboard = info.draggingPasteboard()
        
        if let idPlist = pboard.propertyList(forType: PasteboardType) {
            let elementID = E.ID.fromPlist(idPlist as AnyObject)!
            if let srcIndex = model.data.indexForID(elementID, elements) {
                if proposedIndex >= 0 && proposedIndex != srcIndex && proposedIndex != srcIndex + 1 {
                    return NSDragOperation.move
                }
            }
        }
        
        return NSDragOperation()
    }

    open func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        let pboard = info.draggingPasteboard()
        
        if let idPlist = pboard.propertyList(forType: PasteboardType), let move = model.move {
            let elementID = E.ID.fromPlist(idPlist as AnyObject)!
            if let srcIndex = model.data.indexForID(elementID, elements) {
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
        if let textField = view.textField as? TextField {
            textField.string.unbindAll()
            switch model.cellText(element.data) {
            case .readOnly(let text):
                _ = textField.string <~ text
            case .readWrite(let text):
                _ = textField.string <~> text
            case .asyncReadOnly(let text):
                _ = textField.string <~ text
            case .asyncReadWrite(let text):
                _ = textField.string <~> text
            }
        }
        if let imageView = view.imageView as? ImageView {
            imageView.img.unbindAll()
            if let image = model.cellImage?(element.data) {
                _ = imageView.img <~ image
            }
        }
        return view
    }
    
    open func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        return false
    }
    
    open func outlineView(_ outlineView: NSOutlineView, menuForItem item: AnyObject) -> NSMenu? {
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

    fileprivate func arrayChanged(_ arrayChanges: [ArrayChange<E>]) {
        let animation: NSTableViewAnimationOptions = animateChanges ? [.effectFade] : NSTableViewAnimationOptions()
        
        outlineView.beginUpdates()

        // Record changes that were made to the array relative to its previous state
        for change in arrayChanges {
            switch change {
            case .initial(_):
                outlineView.reloadData()
                
            case let .insert(index):
                let rows = IndexSet(integer: index)
                outlineView.insertItems(at: rows, inParent: nil, withAnimation: animation)
                
            case let .delete(index):
                let rows = IndexSet(integer: index)
                outlineView.removeItems(at: rows, inParent: nil, withAnimation: animation)
                
            case let .move(srcIndex, dstIndex):
                outlineView.moveItem(at: srcIndex, inParent: nil, to: dstIndex, inParent: nil)
            }
        }

        // XXX: This prevents a call to selection.set(); we need to figure out a better way, so that
        // if the selection changes as a result of e.g. deleting an item, we update our selection
        // state, but do it in a way that doesn't go through the undo manager
        //selfInitiatedSelectionChange = true
        outlineView.endUpdates()
        //selfInitiatedSelectionChange = false
    }
}
