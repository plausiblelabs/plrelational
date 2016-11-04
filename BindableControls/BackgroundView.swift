//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding

open class BackgroundView: NSView {
    
    public lazy var visible: BindableProperty<Bool> = WriteOnlyProperty(set: { [weak self] value, _ in
        self?.isHidden = !value
    })

    public var backgroundColor: NSColor?
    
    open override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        if let bg = backgroundColor {
            bg.setFill()
            NSBezierPath.fill(dirtyRect)
        }
    }
    
    open override var isFlipped: Bool {
        return true
    }
}
