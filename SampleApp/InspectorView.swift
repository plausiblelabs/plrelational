//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding
import BindableControls

// Note: Normally this would be an NSView subclass, but for the sake of expedience we defined the UI in
// a single Document.xib, so this class simply manages a subset of views defined in that xib.
class InspectorView {
    
    private let treeView: TreeView<RowTreeNode>
    
    init(model: TreeViewModel<RowTreeNode>, outlineView: NSOutlineView) {
        self.treeView = TreeView(model: model, outlineView: outlineView)
        self.treeView.autoExpand = true
    }
}
