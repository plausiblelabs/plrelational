//
// Copyright (c) 2015 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa

class BackgroundView: NSView {
    
    var backgroundColor: NSColor?
    
    override func drawRect(dirtyRect: NSRect) {
        super.drawRect(dirtyRect)
        
        if let bg = backgroundColor {
            bg.setFill()
            NSBezierPath.fillRect(dirtyRect)
        }
    }
    
    override var flipped: Bool {
        return true
    }
}
