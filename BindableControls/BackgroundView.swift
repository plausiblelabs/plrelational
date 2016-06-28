//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding

public class BackgroundView: NSView {
    
    public lazy var visible: BindableProperty<Bool> = WriteOnlyProperty({ [weak self] value, _ in
        self?.hidden = !value
    })

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
