//
//  InspectorView.swift
//  Relational
//
//  Created by Chris Campbell on 5/15/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Cocoa
import libRelational

// Note: Normally this would be an NSView subclass, but for the sake of expedience we defined the UI in
// a single Document.xib, so this class simply manages a subset of views defined in that xib.
class InspectorView {
    
    private let treeView: TreeView<Row>
    
    init(outlineView: NSOutlineView, docModel: DocModel) {
        self.treeView = TreeView(outlineView: outlineView, model: docModel.inspectorTreeViewModel)
        self.treeView.autoExpand = true
    }
}
