//
//  Document.swift
//  SampleApp
//
//  Created by Chris Campbell on 5/2/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Cocoa
import libRelational

protocol ExtOutlineViewDelegate: NSOutlineViewDelegate {
    func outlineView(outlineView: NSOutlineView, menuForItem item: AnyObject) -> NSMenu?
}

class ExtOutlineView: NSOutlineView {
    
    override func validateProposedFirstResponder(responder: NSResponder, forEvent event: NSEvent?) -> Bool {
        // XXX: The following prevents the text field from becoming first responder if it is right-clicked
        // (which should instead cause the context menu to be shown)
        if let event = event {
            if event.type == .RightMouseDown || (event.type == .LeftMouseDown && event.modifierFlags.contains(.ControlKeyMask)) {
                return false
            } else {
                return super.validateProposedFirstResponder(responder, forEvent: event)
            }
        } else {
            return super.validateProposedFirstResponder(responder, forEvent: event)
        }
    }
    
    override func menuForEvent(event: NSEvent) -> NSMenu? {
        // Notify the delegate if a context menu is requested for an item
        let point = self.convertPoint(event.locationInWindow, fromView: nil)
        let row = self.rowAtPoint(point)
        let item = self.itemAtRow(row)
        if item == nil {
            return nil
        }
        return (self.delegate() as! ExtOutlineViewDelegate).outlineView(self, menuForItem: item!)
    }
}

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
    @IBOutlet var itemTypeLabel: TextField!
    @IBOutlet var nameTextField: TextField!
    @IBOutlet var nameLabel: TextField!
    @IBOutlet var noSelectionLabel: TextField!

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
        
        func makeDB() -> (path: String, db: SQLiteDatabase) {
            let tmp = NSTemporaryDirectory() as NSString
            let dbname = "testing-\(NSUUID()).db"
            let path = tmp.stringByAppendingPathComponent(dbname)
            _ = try? NSFileManager.defaultManager().removeItemAtPath(path)
            
            let db = try! SQLiteDatabase(path)
            
            return (path, db)
        }
        
        // Prepare the schemas
        let db = makeDB().db
        assert(db.createRelation("page", scheme: ["id", "name"]).ok != nil)
        
        // Prepare the default document data
        var idval: Int64 = 1
        let pages = db["page", ["id", "name"]]
        func addPage(name: String) {
            pages.add(["id": RelationValue(idval), "name": RelationValue(name)])
            idval += 1
        }
        addPage("Page1")
        addPage("Page2")
        addPage("Page3")
    }
}
