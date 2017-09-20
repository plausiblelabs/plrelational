//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import AppKit
import PLRelationalBinding
import PLBindableControls

/// Normally it would not be necessary to subclass ListView, but we do that here just to customize the row selection
/// color to make the search results a bit more readable.
class ResultsListView: ListView<RowArrayElement> {
    
    override func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        let identifier = "RowView"
        if let rowView = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: identifier), owner: self) {
            return rowView as? NSTableRowView
        } else {
            let rowView = OutlineRowView(frame: NSZeroRect, rowHeight: outlineView.rowHeight)
            rowView.identifier = NSUserInterfaceItemIdentifier(rawValue: identifier)
            return rowView
        }
    }
}

private class OutlineRowView: NSTableRowView {
    let rowHeight: CGFloat
    
    init(frame: NSRect, rowHeight: CGFloat) {
        self.rowHeight = rowHeight
        super.init(frame: frame)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func drawSelection(in dirtyRect: NSRect) {
        var selectionRect = self.bounds
        selectionRect.origin.y = self.bounds.height - rowHeight
        selectionRect.size.height = rowHeight
        let color = NSColor(red: 178.0/255.0, green: 223.0/255.0, blue: 255.0/255.0, alpha: 1.0)
        color.setFill()
        selectionRect.fill()
    }
}
