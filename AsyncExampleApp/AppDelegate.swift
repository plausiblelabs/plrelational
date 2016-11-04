//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelational
import PLRelationalBinding
import BindableControls

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    
    @IBOutlet weak var window: NSWindow!
    @IBOutlet var nameField1: TextField!
    @IBOutlet var nameField2: TextField!
    @IBOutlet var nameLabel: TextField!
    @IBOutlet var salesLabel: TextField!
    
    var nsUndoManager: SPUndoManager!
    var model: ViewModel!
    
    func applicationDidFinishLaunching(aNotification: NSNotification) {
        window.delegate = self
        
        // Prepare the undo manager
        nsUndoManager = SPUndoManager()
        let undoManager = UndoManager(nsmanager: nsUndoManager)
        
        // Bind the views to the view model
        model = ViewModel(undoManager: undoManager)
        nameField1.string <~> model.name
        nameField2.string <~> model.name
        nameLabel.string <~ model.name
        salesLabel.string <~ model.sales
    }
    
    func windowWillReturnUndoManager(window: NSWindow) -> NSUndoManager? {
        return nsUndoManager
    }
}
