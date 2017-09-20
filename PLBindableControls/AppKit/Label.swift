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
    
    public private(set) lazy var string: BindableProperty<String> = WriteOnlyProperty(set: { [weak self] value, _ in
        self?.stringValue = value
    })

    public private(set) lazy var attributedString: BindableProperty<NSAttributedString> = WriteOnlyProperty(set: { [weak self] value, _ in
        self?.attributedStringValue = value
    })

    public private(set) lazy var bindable_textColor: BindableProperty<NSColor> = WriteOnlyProperty(set: { [weak self] value, _ in
        self?.textColor = value
    })
    
    public private(set) lazy var visible: BindableProperty<Bool> = WriteOnlyProperty(set: { [weak self] value, _ in
        self?.isHidden = !value
    })
}

extension Label {
    fileprivate func setup() {
        self.drawsBackground = false
        self.isBezeled = false
        self.isEditable = false
    }
}
