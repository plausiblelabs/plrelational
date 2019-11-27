//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelational
import PLRelationalBinding
import PLBindableControls

class ChecklistView: NSView {

    @IBOutlet var view: NSView!
    @IBOutlet var newItemField: EphemeralTextField!
    @IBOutlet var outlineView: NSOutlineView!

    private var listView: ListView<RowArrayElement>!
    
    private let model: ChecklistViewModel

    init(frame: NSRect, model: ChecklistViewModel) {
        self.model = model
        
        super.init(frame: frame)
        
        // Load the xib and bind to it
        Bundle.main.loadNibNamed("ChecklistView", owner: self, topLevelObjects: nil)
        view.frame = self.bounds
        addSubview(view)
        
        // Configure the views
        outlineView.backgroundColor = .clear
        
        // Bind to our view model
        
        // REQ-1
        newItemField.strings ~~> model.addNewItem
        
        // REQ-2
        listView = CustomListView(model: model.itemsListModel,
                                  outlineView: outlineView)
        listView.animateChanges = true
        listView.configureCell = { view, row in
            let cellView = view as! ChecklistCellView
            
            // REQ-3
            let checkbox = cellView.checkbox!
            checkbox.checkState.unbindAll()
            checkbox.checkState <~> model.itemCompleted(for: row)
            
            // REQ-4
            let textField = cellView.textField as! TextField
            textField.string.unbindAll()
            textField.string <~> model.itemTitle(for: row)
            
            // REQ-5
            let detailLabel = cellView.detailLabel!
            detailLabel.string.unbindAll()
            detailLabel.string <~ model.itemTags(for: row)
        }

        // REQ-6
        listView.selection <~> model.itemsListSelection
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class ChecklistCellView: NSTableCellView {
    @IBOutlet var checkbox: Checkbox!
    @IBOutlet var detailLabel: Label!
}

/// Normally it would not be necessary to subclass ListView, but we do that here just to customize the row backgrounds.
private class CustomListView: ListView<RowArrayElement> {
    
    override func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        let identifier = NSUserInterfaceItemIdentifier("RowView")
        if let rowView = outlineView.makeView(withIdentifier: identifier, owner: self) {
            return rowView as? NSTableRowView
        } else {
            let rowView = OutlineRowView(frame: NSZeroRect, rowHeight: outlineView.rowHeight)
            rowView.identifier = identifier
            return rowView
        }
    }
}

private let padX: CGFloat = 1
private let cornerRadius: CGFloat = 4
private let strongColor: NSColor = NSColor(red: 41.0/255.0, green: 191.0/255.0, blue: 250.0/255.0, alpha: 1.0)
private let weakColor: NSColor = strongColor.withAlphaComponent(0.5)

private class OutlineRowView: NSTableRowView {
    let rowHeight: CGFloat
    
    init(frame: NSRect, rowHeight: CGFloat) {
        self.rowHeight = rowHeight
        super.init(frame: frame)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func drawBackground(in dirtyRect: NSRect) {
        drawRounded(.white)
    }
    
    override func drawSelection(in dirtyRect: NSRect) {
        drawRounded(self.isEmphasized ? strongColor : weakColor)
    }
    
    private func drawRounded(_ color: NSColor) {
        var rect = self.bounds
        rect.origin.x = padX
        rect.origin.y = rect.height - rowHeight
        rect.size.width -= padX * 2
        rect.size.height = rowHeight
        color.setFill()
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        path.fill()
    }
}
