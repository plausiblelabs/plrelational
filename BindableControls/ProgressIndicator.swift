//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding

public class ProgressIndicator: NSProgressIndicator {
    
    public lazy var visible: BindableProperty<Bool> = WriteOnlyProperty { [weak self] value, _ in
        self?.hidden = !value
        if value {
            self?.startAnimation(nil)
        } else {
            self?.stopAnimation(nil)
        }
    }
}
