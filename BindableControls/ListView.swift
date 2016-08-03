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
    public let move: ((srcIndex: Int, dstIndex: Int) -> Void)?
    public let selection: AsyncReadWriteProperty<Set<E.ID>>
    public let cellIdentifier: (E.Data) -> String
    public let cellText: (E.Data) -> CellTextProperty
    public let cellImage: ((E.Data) -> ReadableProperty<Image>)?

    public init(
        data: ArrayProperty<E>,
        contextMenu: ((E.Data) -> ContextMenu?)?,
        move: ((srcIndex: Int, dstIndex: Int) -> Void)?,
        selection: AsyncReadWriteProperty<Set<E.ID>>,
        cellIdentifier: (E.Data) -> String,
        cellText: (E.Data) -> CellTextProperty,
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
public class ListView<E: ArrayElement>: NSObject, NSOutlineViewDataSource, ExtOutlineViewDelegate {

    private let model: ListViewModel<E>
    private let outlineView: NSOutlineView

    private var elements: [E] {
        return model.data.value ?? []
    }
    
    private lazy var selection: ExternalValueProperty<Set<E.ID>> = ExternalValueProperty(
        get: { [unowned self] in
            var itemIDs: [E.ID] = []
            self.outlineView.selectedRowIndexes.enumerateIndexesUsingBlock { (index, stop) -> Void in
                if let element = self.outlineView.itemAtRow(index) as? E {
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
                    let index = self.outlineView.rowForItem(element)
                    if index >= 0 {
                        indexes.addIndex(index)
                    }
                }
            }
            self.outlineView.selectRowIndexes(indexes, byExtendingSelection: false)
        }
    )

    private var arrayObserverRemoval: ObserverRemoval?
    //private var selfInitiatedSelectionChange = false
    
    /// Whether to animate insert/delete changes with a fade.
    public var animateChanges = false

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
        selection <~> model.selection
        
        outlineView.setDelegate(self)
        outlineView.setDataSource(self)
        
        // Enable drag-and-drop
        outlineView.registerForDraggedTypes([PasteboardType])
        outlineView.verticalMotionCanBeginDrag = true
        
        // Load the initial data
        model.data.start()
    }

    deinit {
        arrayObserverRemoval?()
    }

    // MARK: NSOutlineViewDataSource

    public func outlineView(outlineView: NSOutlineView, numberOfChildrenOfItem item: AnyObject?) -> Int {
        return elements.count
    }
    
    public func outlineView(outlineView: NSOutlineView, child index: Int, ofItem item: AnyObject?) -> AnyObject {
        return elements[index]
    }
    
    public func outlineView(outlineView: NSOutlineView, isItemExpandable item: AnyObject) -> Bool {
        return false
    }
    
    public func outlineView(outlineView: NSOutlineView, pasteboardWriterForItem item: AnyObject) -> NSPasteboardWriting? {
        if model.move == nil {
            return nil
        }
        
        let element = item as! E
        let pboardItem = NSPasteboardItem()
        pboardItem.setPropertyList(element.id.toPlist(), forType: PasteboardType)
        return pboardItem
    }
    
    public func outlineView(outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem: AnyObject?, proposedChildIndex proposedIndex: Int) -> NSDragOperation {
        let pboard = info.draggingPasteboard()
        
        if let idPlist = pboard.propertyListForType(PasteboardType) {
            let elementID = E.ID.fromPlist(idPlist)!
            if let srcIndex = model.data.indexForID(elementID, elements) {
                if proposedIndex >= 0 && proposedIndex != srcIndex && proposedIndex != srcIndex + 1 {
                    return NSDragOperation.Move
                }
            }
        }
        
        return NSDragOperation.None
    }

    public func outlineView(outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: AnyObject?, childIndex index: Int) -> Bool {
        let pboard = info.draggingPasteboard()
        
        if let idPlist = pboard.propertyListForType(PasteboardType), move = model.move {
            let elementID = E.ID.fromPlist(idPlist)!
            if let srcIndex = model.data.indexForID(elementID, elements) {
                move(srcIndex: srcIndex, dstIndex: index)
                return true
            }
        }
        
        return false
    }

    // MARK: ExtOutlineViewDelegate

    public func outlineView(outlineView: NSOutlineView, viewForTableColumn: NSTableColumn?, item: AnyObject) -> NSView? {
        let element = item as! E
        let identifier = model.cellIdentifier(element.data)
        let view = outlineView.makeViewWithIdentifier(identifier, owner: self) as! NSTableCellView
        if let textField = view.textField as? TextField {
            textField.string.unbindAll()
            switch model.cellText(element.data) {
            case .ReadOnly(let text):
                textField.string <~ text
            case .ReadWrite(let text):
                textField.string <~> text
            case .AsyncReadOnly(let text):
                textField.string <~ text
            case .AsyncReadWrite(let text):
                textField.string <~> text
            }
        }
        if let imageView = view.imageView as? ImageView {
            imageView.img.unbindAll()
            if let image = model.cellImage?(element.data) {
                imageView.img <~ image
            }
        }
        return view
    }
    
    public func outlineView(outlineView: NSOutlineView, isGroupItem item: AnyObject) -> Bool {
        return false
    }
    
    public func outlineView(outlineView: NSOutlineView, menuForItem item: AnyObject) -> NSMenu? {
        let element = item as! E
        return model.contextMenu?(element.data).map{$0.nsmenu}
    }
    
    public func outlineView(outlineView: NSOutlineView, shouldSelectItem item: AnyObject) -> Bool {
        return true
    }
    
    public func outlineViewSelectionDidChange(notification: NSNotification) {
        // TODO: Do we need this flag anymore?
//        if selfInitiatedSelectionChange {
//            return
//        }

//        selfInitiatedSelectionChange = true
        selection.changed(transient: false)
//        selfInitiatedSelectionChange = false
    }

    // MARK: Property observers

    private func arrayChanged(arrayChanges: [ArrayChange<E>]) {
        let animation: NSTableViewAnimationOptions = animateChanges ? [.EffectFade] : [.EffectNone]
        
        outlineView.beginUpdates()

        // Record changes that were made to the array relative to its previous state
        for change in arrayChanges {
            switch change {
            case .Initial(_):
                outlineView.reloadData()
                
            case let .Insert(index):
                let rows = NSIndexSet(index: index)
                outlineView.insertItemsAtIndexes(rows, inParent: nil, withAnimation: animation)
                
            case let .Delete(index):
                let rows = NSIndexSet(index: index)
                outlineView.removeItemsAtIndexes(rows, inParent: nil, withAnimation: animation)
                
            case let .Move(srcIndex, dstIndex):
                outlineView.moveItemAtIndex(srcIndex, inParent: nil, toIndex: dstIndex, inParent: nil)
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
