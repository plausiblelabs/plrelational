//
// Copyright (c) 2015 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding

class BackgroundView: NSView {
    
    private let bindings = BindingSet()
    
    var visible: ValueBinding<Bool>? {
        didSet {
            bindings.register("visible", visible, { [weak self] value in
                self?.hidden = !value
            })
        }
    }

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
