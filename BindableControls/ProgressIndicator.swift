//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding

public class ProgressIndicator: NSProgressIndicator {
    
    private let bindings = BindingSet()
    
    public var visible: ObservableValue<Bool>? {
        didSet {
            bindings.observe(visible, "visible", { [weak self] value in
                self?.hidden = !value
            })
        }
    }
}
