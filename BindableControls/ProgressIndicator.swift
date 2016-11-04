//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelationalBinding

open class ProgressIndicator: NSProgressIndicator {
    
    public lazy var visible: BindableProperty<Bool> = WriteOnlyProperty(set: { [weak self] value, _ in
        self?.isHidden = !value
        if value {
            self?.startAnimation(nil)
        } else {
            self?.stopAnimation(nil)
        }
    })
}
