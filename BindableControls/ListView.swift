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
    let data: ObservableArray<E>
    let contextMenu: ((E.Data) -> ContextMenu?)?
    // Note: dstIndex is relative to the state of the array *before* the item is removed.
    let move: ((srcIndex: Int, dstIndex: Int) -> Void)?
    let selection: MutableObservableValue<Set<E.ID>>
    let cellIdentifier: (E.Data) -> String
    let cellText: (E.Data) -> ObservableValue<String>
    let cellImage: ((E.Data) -> ObservableValue<Image>)?

    public init(
        data: ObservableArray<E>,
        contextMenu: ((E.Data) -> ContextMenu?)?,
        move: ((srcIndex: Int, dstIndex: Int) -> Void)?,
        selection: MutableObservableValue<Set<E.ID>>,
        cellIdentifier: (E.Data) -> String,
        cellText: (E.Data) -> ObservableValue<String>,
        cellImage: ((E.Data) -> ObservableValue<Image>)?)
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

    private var arrayObserverRemoval: ObserverRemoval?
    private var selectionObserverRemoval: ObserverRemoval?
    private var selfInitiatedSelectionChange = false
    
    /// Whether to animate insert/delete changes with a fade.
    public var animateChanges = false

    public init(model: ListViewModel<E>, outlineView: NSOutlineView) {
        self.model = model
        self.outlineView = outlineView
        
        super.init()
        
        arrayObserverRemoval = model.data.addChangeObserver({ [weak self] changes in self?.arrayChanged(changes) })
        selectionObserverRemoval = model.selection.addChangeObserver({ [weak self] _ in self?.selectionChanged() })
        
        outlineView.setDelegate(self)
        outlineView.setDataSource(self)
        
        // Enable drag-and-drop
        outlineView.registerForDraggedTypes([PasteboardType])
        outlineView.verticalMotionCanBeginDrag = true
    }

    deinit {
        arrayObserverRemoval?()
        selectionObserverRemoval?()
    }

    // MARK: NSOutlineViewDataSource

    public func outlineView(outlineView: NSOutlineView, numberOfChildrenOfItem item: AnyObject?) -> Int {
        return model.data.elements.count
    }
    
    public func outlineView(outlineView: NSOutlineView, child index: Int, ofItem item: AnyObject?) -> AnyObject {
        return model.data.elements[index]
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
            if let srcIndex = model.data.indexForID(elementID) {
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
            if let srcIndex = model.data.indexForID(elementID) {
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
            textField.string = model.cellText(element.data)
        }
        if let imageView = view.imageView as? ImageView {
            imageView.img = model.cellImage?(element.data)
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
        if selfInitiatedSelectionChange {
            return
        }
        
        selfInitiatedSelectionChange = true
        
        var itemIDs: [E.ID] = []
        outlineView.selectedRowIndexes.enumerateIndexesUsingBlock { (index, stop) -> Void in
            if let element = self.outlineView.itemAtRow(index) as? E {
                itemIDs.append(element.id)
            }
        }
        model.selection.update(Set(itemIDs), ChangeMetadata(transient: false))
        
        selfInitiatedSelectionChange = false
    }

    // MARK: Binding observers
    
    private func selectionChanged() {
        if selfInitiatedSelectionChange {
            return
        }
        
        let indexes = NSMutableIndexSet()
        for id in model.selection.value {
            if let element = model.data.elementForID(id) {
                // TODO: This is inefficient
                let index = outlineView.rowForItem(element)
                if index >= 0 {
                    indexes.addIndex(index)
                }
            }
        }
        
        selfInitiatedSelectionChange = true
        outlineView.selectRowIndexes(indexes, byExtendingSelection: false)
        selfInitiatedSelectionChange = false
    }

    private func arrayChanged(changes: [ArrayChange]) {
        let animation: NSTableViewAnimationOptions = animateChanges ? [.EffectFade] : [.EffectNone]
        
        outlineView.beginUpdates()
        
        for change in changes {
            switch change {
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

        outlineView.endUpdates()
    }
}
