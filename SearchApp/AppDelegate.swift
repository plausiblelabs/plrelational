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
    @IBOutlet var textField: TextField!
    @IBOutlet var outlineView: ExtOutlineView!
    @IBOutlet var recordButton: Button!
    @IBOutlet var saveButton: Button!
    @IBOutlet var progressIndicator: ProgressIndicator!
    
    var nsUndoManager: SPUndoManager!
    var model: ViewModel!
    var listView: ListView<RowArrayElement>!
    
    func applicationDidFinishLaunching(aNotification: NSNotification) {
        window.delegate = self
        
        // Prepare the undo manager
        nsUndoManager = SPUndoManager()
        let undoManager = UndoManager(nsmanager: nsUndoManager)

        // Bind the views to the view model
        model = ViewModel(undoManager: undoManager)
        textField.string <~> model.queryString
        listView = ListView(model: model.listViewModel, outlineView: outlineView)
        progressIndicator.visible <~ model.progressVisible
        recordButton.disabled <~ model.recordDisabled
        //recordButton.clicked = model.recordClicked
        saveButton.disabled <~ model.saveDisabled
        //saveButton.clicked = model.saveClicked
    }
    
    func windowWillReturnUndoManager(window: NSWindow) -> NSUndoManager? {
        return nsUndoManager
    }
}
