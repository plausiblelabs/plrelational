//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa

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
