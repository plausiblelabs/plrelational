//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelational
import PLRelationalBinding
import PLBindableControls

class DetailView: BackgroundView {
    
    @IBOutlet var view: NSView!
    @IBOutlet var checkbox: Checkbox!
    @IBOutlet var textField: TextField!
    @IBOutlet var tagsOutlineView: NSOutlineView!
    @IBOutlet var createdOnLabel: Label!
    @IBOutlet var deleteButton: Button!
    
    private let model: DetailViewModel
    
    init(frame: NSRect, model: DetailViewModel) {
        self.model = model
        
        super.init(frame: frame)
        
        // Load the xib and bind to it
        Bundle.main.loadNibNamed("DetailView", owner: self, topLevelObjects: nil)
        view.frame = self.bounds
        addSubview(view)
        
        // Configure the background
        self.backgroundColor = .white
        self.wantsLayer = true
        self.layer!.cornerRadius = 4
        
        // Bind to our view model
        textField.string <~> model.itemText
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
