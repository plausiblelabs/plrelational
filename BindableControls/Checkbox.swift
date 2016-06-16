//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding

public class Checkbox: NSButton {
    
    private let bindings = BindingSet()
    
    public var checked: MutableObservableValue<CheckState>? {
        didSet {
            bindings.observe(checked, "checked", { [weak self] value in
                // Only allow mixed state if we are starting in a mixed state; otherwise we
                // use simple two-state mode
                self?.allowsMixedState = value == .Mixed
                self?.state = value.nsValue
            })
        }
    }
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setButtonType(.SwitchButton)
        target = self
        action = #selector(checkboxToggled(_:))
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setButtonType(.SwitchButton)
        target = self
        action = #selector(checkboxToggled(_:))
    }
    
    @objc func checkboxToggled(sender: Checkbox) {
        guard let checked = checked else { return }
        
        // Note that by the time this function is called, `state` already reflects the new value.
        // Cocoa always wants to cycle through the states (including mixed), but we only want the user
        // to be able to choose on/off; we shouldn't ever see a mixed state here (Cocoa goes from
        // Mixed to On), but just in case, treat it as On and disable allowsMixedState.
        let mixed = state == NSMixedState
        allowsMixedState = false
        let newState: CheckState
        if mixed {
            newState = .On
        } else {
            newState = state == NSOnState ? .On : .Off
        }
        bindings.update(checked, newValue: newState)
    }
    
    public override func accessibilityValue() -> AnyObject? {
        return CheckState(state).rawValue
    }
}
