//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa

public protocol ExtOutlineViewDelegate: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, menuForItem item: Any) -> NSMenu?
}

open class ExtOutlineView: NSOutlineView {
    
    open override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
        // XXX: The following prevents the text field from becoming first responder if it is right-clicked
        // (which should instead cause the context menu to be shown)
        if let event = event {
            if event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) {
                return false
            } else {
                return super.validateProposedFirstResponder(responder, for: event)
            }
        } else {
            return super.validateProposedFirstResponder(responder, for: event)
        }
    }
    
    open override func menu(for event: NSEvent) -> NSMenu? {
        // Notify the delegate if a context menu is requested for an item
        let point = self.convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        let item = self.item(atRow: row)
        if item == nil {
            return nil
        }
        return (self.delegate as! ExtOutlineViewDelegate).outlineView(self, menuForItem: item!)
    }
}
