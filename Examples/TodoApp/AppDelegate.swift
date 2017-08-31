//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelational
import PLRelationalBinding
import PLBindableControls

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    
    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var listContainer: NSView!
    @IBOutlet weak var detailContainer: NSView!
    @IBOutlet weak var noSelectionLabel: Label!
    
    private var checklistView: ChecklistView!
    private var detailView: DetailView!
    
    private var model: Model!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        window.delegate = self
        
        // Initialize our model
        model = Model()
        
        // Add the checklist view to the left side
        let checklistViewModel = ChecklistViewModel(model: model)
        checklistView = ChecklistView(frame: listContainer.bounds, model: checklistViewModel)
        listContainer.addSubview(checklistView)
        
        // Add the detail view to the left side
        let detailViewModel = DetailViewModel(model: model)
        detailView = DetailView(frame: detailContainer.bounds, model: detailViewModel)
        detailContainer.addSubview(detailView)
    }
}
