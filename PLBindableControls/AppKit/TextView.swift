//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelationalBinding

open class TextView: NSTextView, NSTextViewDelegate {

    private lazy var _text: ExternalValueProperty<String> = ExternalValueProperty(
        get: { [unowned self] in
            self.string ?? ""
        },
        set: { [unowned self] value, _ in
            self.string = value
        }
    )
    public var text: ReadWriteProperty<String> { return _text }
    
    public override init(frame: NSRect) {
        super.init(frame: frame)
        
        self.delegate = self
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        self.delegate = self
    }
    
    open func textDidEndEditing(_ notification: Notification) {
        _text.changed(transient: false)
    }
}
