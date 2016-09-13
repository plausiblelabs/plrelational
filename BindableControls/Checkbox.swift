//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding

open class Checkbox: NSButton {
    
    fileprivate lazy var _checked: ExternalValueProperty<CheckState> = ExternalValueProperty(
        get: { [unowned self] in
            return CheckState(self.state)
        },
        set: { [unowned self] value, _ in
            // Only allow mixed state if we are starting in a mixed state; otherwise we
            // use simple two-state mode
            self.allowsMixedState = value == .Mixed
            self.state = value.nsValue
        }
    )
    open var checked: ReadWriteProperty<CheckState> { return _checked }
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setButtonType(.switch)
        target = self
        action = #selector(checkboxToggled(_:))
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setButtonType(.switch)
        target = self
        action = #selector(checkboxToggled(_:))
    }
    
    @objc func checkboxToggled(_ sender: Checkbox) {
        // Note that by the time this function is called, `state` already reflects the new value.
        // Cocoa always wants to cycle through the states (including mixed), but we only want the user
        // to be able to choose on/off, so disable allowsMixedState here.
        allowsMixedState = false
        _checked.changed(transient: false)
    }
    
    open override func accessibilityValue() -> Any? {
        return CheckState(state).rawValue
    }
}
