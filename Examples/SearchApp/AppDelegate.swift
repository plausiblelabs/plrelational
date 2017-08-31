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
    @IBOutlet var queryField: TextField!
    @IBOutlet var outlineView: ExtOutlineView!
    @IBOutlet var noResultsLabel: Label!
    @IBOutlet var personNameLabel: Label!
    @IBOutlet var personBioLabel: Label!
    
    private var nsUndoManager: SPUndoManager!
    private var model: ViewModel!
    private var resultsListView: ListView<RowArrayElement>!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        window.delegate = self
        queryField.deliverTransientChanges = true
        
        // Prepare the undo manager
        nsUndoManager = SPUndoManager()
        let undoManager = PLBindableControls.UndoManager(nsmanager: nsUndoManager)
        
        // Bind the views to the view model
        model = ViewModel(undoManager: undoManager)
        model.queryString <~ queryField.string
        
        resultsListView = ResultsListView(model: model.resultsListModel, outlineView: outlineView)
        resultsListView.reloadCellOnUpdate = true
        resultsListView.selection <~> model.resultsListSelection
        resultsListView.configureCell = { view, row in
            view.textField?.attributedStringValue = SearchResult.highlightedString(from: row)
        }
        
        noResultsLabel.visible <~ not(model.hasResults)
        personNameLabel.string <~ model.selectedPersonName
        personBioLabel.string <~ model.selectedPersonBio
    }
    
    func windowWillReturnUndoManager(_ window: NSWindow) -> Foundation.UndoManager? {
        return nsUndoManager
    }
}
