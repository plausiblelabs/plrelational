//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding

public class ProgressIndicator: NSProgressIndicator {
    
    public lazy var visible: Property<Bool> = Property { [weak self] value, _ in
        self?.hidden = !value
    }
}
