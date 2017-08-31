//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelational
import PLRelationalBinding

class ChecklistView: NSView {

    @IBOutlet var view: NSView!
    @IBOutlet var outlineView: NSOutlineView!

    private let model: ChecklistViewModel

    init(frame: NSRect, model: ChecklistViewModel) {
        self.model = model
        
        super.init(frame: frame)
        
        Bundle.main.loadNibNamed("ChecklistView", owner: self, topLevelObjects: nil)
        view.frame = self.bounds
        addSubview(view)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

}
