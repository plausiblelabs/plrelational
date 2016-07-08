//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import libRelational
import Binding
import BindableControls

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    
    @IBOutlet weak var window: NSWindow!
    @IBOutlet var textField1: TextField!
    @IBOutlet var textField2: TextField!
    @IBOutlet var label: TextField!
    
    var nsUndoManager: SPUndoManager!
    var model: ViewModel!
    
    func applicationDidFinishLaunching(aNotification: NSNotification) {
        window.delegate = self
        
        // Prepare the undo manager
        nsUndoManager = SPUndoManager()
        let undoManager = UndoManager(nsmanager: nsUndoManager)
        
        // Bind the views to the view model
        model = ViewModel(undoManager: undoManager)
        textField1.string <~> model.string
        textField2.string <~> model.string
        label.string <~ model.string
    }
    
    func windowWillReturnUndoManager(window: NSWindow) -> NSUndoManager? {
        return nsUndoManager
    }
}
