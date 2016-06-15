//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding

public class BackgroundView: NSView {
    
    private let bindings = BindingSet()
    
    public var visible: ObservableValue<Bool>? {
        didSet {
            bindings.observe(visible, "visible", { [weak self] value in
                self?.hidden = !value
            })
        }
    }

    public var backgroundColor: NSColor?
    
    public override func drawRect(dirtyRect: NSRect) {
        super.drawRect(dirtyRect)
        
        if let bg = backgroundColor {
            bg.setFill()
            NSBezierPath.fillRect(dirtyRect)
        }
    }
    
    public override var flipped: Bool {
        return true
    }
}
