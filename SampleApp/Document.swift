//
//  Document.swift
//  SampleApp
//
//  Created by Chris Campbell on 5/2/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Cocoa

class Document: NSDocument {

    @IBOutlet var mainSplitView: NSSplitView!
    @IBOutlet var leftSidebarView: BackgroundView!
    @IBOutlet var leftSidebarSplitView: NSSplitView!
    @IBOutlet var documentOutlineView: ExtOutlineView!
    @IBOutlet var inspectorScrollView: NSScrollView!
    @IBOutlet var inspectorOutlineView: ExtOutlineView!
    @IBOutlet var contentView: BackgroundView!
    @IBOutlet var newItemButton: NSPopUpButton!
    @IBOutlet var rightSidebarView: BackgroundView!

    var docOutlineView: DocOutlineView!
    var inspectorView: InspectorView!
    var propertiesView: PropertiesView!
    
    var docModel: DocModel!
    
    override init() {
        super.init()
    }

    override class func autosavesInPlace() -> Bool {
        return false
    }

    override var windowNibName: String? {
        return "Document"
    }

    override func dataOfType(typeName: String) throws -> NSData {
        throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: nil)
    }

    override func readFromData(data: NSData, ofType typeName: String) throws {
        throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: nil)
    }
    
    override func windowControllerDidLoadNib(aController: NSWindowController) {
        super.windowControllerDidLoadNib(aController)
        
        // Set the content background color
        contentView.backgroundColor = NSColor.whiteColor()
        
        // Set the sidebar background color
        let bg = NSColor(calibratedRed: 244/255.0, green: 246/255.0, blue: 249/255.0, alpha: 1.0)
        leftSidebarView.backgroundColor = bg
        documentOutlineView.backgroundColor = bg
        inspectorOutlineView.backgroundColor = bg
        rightSidebarView.backgroundColor = bg

        // Prepare the undo manager
        let nsmanager = SPUndoManager()
        self.undoManager = nsmanager
        let undoManager = UndoManager(nsmanager: nsmanager)
        
        // Create the document model
        docModel = DocModel(undoManager: undoManager)
        docModel.addDefaultData()
        
        // Create the "views"
        docOutlineView = DocOutlineView(model: docModel.docOutlineTreeViewModel, outlineView: documentOutlineView)
        inspectorView = InspectorView(model: docModel.inspectorTreeViewModel, outlineView: inspectorOutlineView)
        propertiesView = PropertiesView(frame: rightSidebarView.bounds, model: docModel.propertiesModel)
        rightSidebarView.addSubview(propertiesView)
    }
    
    @IBAction func newPageAction(sender: NSMenuItem) {
        docModel.newCollection("Page", type: .Page, parentID: nil)
    }
}
