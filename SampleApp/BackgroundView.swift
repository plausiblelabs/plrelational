//
// Copyright (c) 2015 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding

class BackgroundView: NSView {
    
    var visible: ValueBinding<Bool>? {
        didSet {
            visibleBindingRemoval?()
            visibleBindingRemoval = nil
            if let visible = visible {
                hidden = !visible.value
                visibleBindingRemoval = visible.addChangeObserver({ [weak self] in self?.hidden = !visible.value })
            } else {
                hidden = false
            }
        }
    }

    var backgroundColor: NSColor?
    
    private var visibleBindingRemoval: ObserverRemoval?
    
    deinit {
        visibleBindingRemoval?()
    }
    
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
