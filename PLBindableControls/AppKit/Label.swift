//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelationalBinding

open class Label: NSTextField {
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    public private(set) lazy var string: BindableProperty<String> = WriteOnlyProperty(set: { [weak self] in
        self?.stringValue = $0.0
    })
    
    public private(set) lazy var bindable_textColor: BindableProperty<NSColor> = WriteOnlyProperty(set: { [weak self] in
        self?.textColor = $0.0
    })
}

extension Label {
    fileprivate func setup() {
        self.drawsBackground = false
        self.isBezeled = false
        self.isEditable = false
    }
}
