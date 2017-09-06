//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelational
import PLRelationalBinding
import PLBindableControls

class Document: NSDocument {
    
    @IBOutlet var mainSplitView: NSSplitView!
    @IBOutlet var leftSidebarView: BackgroundView!
    @IBOutlet var leftSidebarSplitView: NSSplitView!
    @IBOutlet var documentOutlineView: ExtOutlineView!
    @IBOutlet var inspectorScrollView: NSScrollView!
    @IBOutlet var inspectorOutlineView: ExtOutlineView!
    @IBOutlet var centerView: BackgroundView!
    @IBOutlet var contentView: BackgroundView!
    @IBOutlet var newItemButton: NSPopUpButton!
    @IBOutlet var rightSidebarView: BackgroundView!
    
    @IBOutlet var backButton: Button!
    @IBOutlet var forwardButton: Button!
    
    private var docOutlineView: DocOutlineView!
    private var editorView: EditorView!
    private var sidebarView: SidebarView!
    
    private var _undoManager: PLUndoManager!
    fileprivate var db: DocDatabase!
    fileprivate var docModel: DocModel!
    
    override init() {
        super.init()
        
        // Prepare the undo manager
        _undoManager = UndoManager()
        _undoManager.delegate = self
        self.undoManager = _undoManager.native
    }
    
    override class func autosavesInPlace() -> Bool {
        return false
    }
    
    override var windowNibName: String? {
        return "Document"
    }
    
    override func read(from url: URL, ofType typeName: String) throws {
        switch DocDatabase.open(from: url, undoManager: _undoManager, transactional: true) {
        case .Ok(let db):
            self.db = db
        case .Err:
            // TODO: Use a more specific error code
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError, userInfo: nil)
        }
    }
    
    override func writeSafely(to url: URL, ofType typeName: String, for saveOperation: NSSaveOperationType) throws {
        // TODO
    }
    
    override func windowControllerDidLoadNib(_ windowController: NSWindowController) {
        super.windowControllerDidLoadNib(windowController)
        
        // Set the background colors
        let bg = NSColor(r: 244, g: 246, b: 249)
        leftSidebarView.backgroundColor = bg
        documentOutlineView.backgroundColor = bg
        inspectorOutlineView.backgroundColor = bg
        rightSidebarView.backgroundColor = bg
        contentView.backgroundColor = NSColor(r: 234, g: 236, b: 239)
        
        if db == nil {
            // Create the document database
            db = DocDatabase.create(at: nil, undoManager: _undoManager, transactional: true).ok!
            db.addDefaultData()
        }
        
        // Create the document model
        docModel = DocModel(db: db)
        
        // Create the views and bind to the document model
        docOutlineView = DocOutlineView(model: docModel.docOutlineModel, outlineView: documentOutlineView)
        // XXX: Keep the inspector hidden until it does something useful
        inspectorScrollView.isHidden = true
        leftSidebarView.visible <~ docModel.leftSidebarVisible
        
        editorView = EditorView(frame: contentView.bounds, model: docModel)
        editorView.autoresizingMask = [.viewWidthSizable, .viewHeightSizable]
        contentView.addSubview(editorView)
        
        sidebarView = SidebarView(frame: rightSidebarView.bounds, model: docModel)
        sidebarView.autoresizingMask = [.viewHeightSizable]
        rightSidebarView.addSubview(sidebarView)
        rightSidebarView.visible <~ docModel.rightSidebarVisible
        
//        backButton.clicks ~~> docModel.navigateBackProperty
//        backButton.disabled <~ !docModel.backButtonEnabled
//        forwardButton.clicks ~~> docModel.navigateForwardProperty
//        forwardButton.disabled <~ !docModel.forwardButtonEnabled
    }
    
    @IBAction func newSharedRelationAction(_ sender: NSMenuItem) {
        // TODO
    }
    
    @IBAction func toggleLeftSidebar(_ sender: NSMenuItem) {
        docModel.leftSidebarVisible.toggle(transient: false)
    }
    
    @IBAction func toggleRightSidebar(_ sender: NSMenuItem) {
        docModel.rightSidebarVisible.toggle(transient: false)
    }
    
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleLeftSidebar)?:
            if docModel.leftSidebarVisible.value {
                menuItem.title = "Hide Navigator"
            } else {
                menuItem.title = "Show Navigator"
            }
            return true
        case #selector(toggleRightSidebar)?:
            if docModel.rightSidebarVisible.value {
                menuItem.title = "Hide Info Inspector"
            } else {
                menuItem.title = "Show Info Inspector"
            }
            return true
        case #selector(newSharedRelationAction)?:
            return db.isNotBusy
        default:
            return true
        }
    }
}

extension Document: UndoManagerDelegate {
    func safeToUndo() -> Bool {
        return db?.isNotBusy ?? false
    }
    
    func safeToRedo() -> Bool {
        return db?.isNotBusy ?? false
    }
}
