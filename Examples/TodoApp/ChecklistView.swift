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
        
        // Bind to our view model
        listView = ListView(model: model.itemsListModel, outlineView: outlineView)
        listView.selection <~> model.itemsListSelection
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

}
