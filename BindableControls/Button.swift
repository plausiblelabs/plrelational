//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding

public class Button: NSButton {

    private let bindings = BindingSet()
    
    public var disabled: ObservableValue<Bool>? {
        didSet {
            bindings.observe(disabled, "disabled", { [weak self] value in
                self?.enabled = !value
            })
        }
    }
    
    public override init(frame: NSRect) {
        super.init(frame: frame)
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}
