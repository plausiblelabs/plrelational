//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelationalBinding
import PLBindableControls

class TextView: NSTextView {
    
    lazy var text: BindableProperty<String> = WriteOnlyProperty(set: { [weak self] in
        self?.string = $0.0
    })
}
