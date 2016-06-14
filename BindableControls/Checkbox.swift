//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding

public class Checkbox: NSButton {
    
    public enum CheckState: String { case
        On = "On",
        Off = "Off",
        Mixed = "Mixed"
        
        public init(_ boolValue: Bool?) {
            switch boolValue {
            case nil:
                self = .Mixed
            case .Some(false):
                self = .Off
            case .Some(true):
                self = .On
            }
        }
        
        init(_ nsValue: Int) {
            switch nsValue {
            case NSMixedState:
                self = .Mixed
            case NSOffState:
                self = .Off
            case NSOnState:
                self = .On
            default:
                preconditionFailure("Must be one of {NSMixedState, NSOnState, NSOffState}")
            }
        }
        
        public var boolValue: Bool {
            switch self {
            case .On:
                return true
            case .Off:
                return false
            case .Mixed:
                preconditionFailure("Cannot represent mixed state as a boolean")
            }
        }

        // Int value is used to set NSButton.state
        var nsValue: Int {
            switch self {
            case .On:
                return NSOnState
            case .Off:
                return NSOffState
            case .Mixed:
                return NSMixedState
            }
        }
    }

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
        fatalError("init(coder:) has not been implemented")
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
