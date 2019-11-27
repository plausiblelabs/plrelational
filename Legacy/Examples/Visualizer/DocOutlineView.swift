//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelationalBinding
import PLBindableControls

class DocOutlineView {
    
    private let treeView: SectionedTreeView<DocOutlineModel>
    
    init(model: DocOutlineModel, outlineView: NSOutlineView) {
        treeView = SectionedTreeView(model: model, outlineView: outlineView)
        treeView.animateChanges = true
        treeView.autoExpand = true
        treeView.rowView = { frame, rowHeight in
            return OutlineRowView(frame: frame, rowHeight: rowHeight)
        }
    }
}
