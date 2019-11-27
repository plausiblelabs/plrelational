//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa

class OutlineRowView: NSTableRowView {
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
        let color = self.isEmphasized ? VisualizerColors.strongHighlight : VisualizerColors.weakHighlight
        color.setFill()
        selectionRect.fill()
    }
}
