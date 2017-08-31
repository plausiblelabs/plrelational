//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelationalBinding

/// A simplified variant of `TextField` that clears the text field whenever new text is committed
/// with the enter key.
open class EphemeralTextField: NSTextField {

    private let _strings = SourceSignal<String>()
    public var strings: Signal<String> { return _strings }
    
    public override init(frame: NSRect) {
        super.init(frame: frame)
        
        target = self
        action = #selector(stringCommitted(_:))
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        target = self
        action = #selector(stringCommitted(_:))
    }
    
    func stringCommitted(_ sender: NSTextField) {
        if !self.stringValue.isEmpty {
            self._strings.notifyValueChanging(self.stringValue)
            self.stringValue = ""
        }
    }
}
