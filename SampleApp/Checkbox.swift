//
//  Checkbox.swift
//  Relational
//
//  Created by Terri Kramer on 5/25/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Cocoa
import Binding

class Checkbox: NSButton {
    
    enum CheckState: String { case
        On = "On",
        Off = "Off",
        Mixed = "Mixed"
        
        init(_ boolValue: Bool?) {
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
        
        var boolValue: Bool {
            switch self {
            case .On:
                return true
            case .Off:
                return false
            case .Mixed:
                preconditionFailure("Cannot represent mixed state as a boolean")
            }
        }
    }

    private var checkStateBindingRemoval: ObserverRemoval?
    
    var checked: BidiValueBinding<CheckState>? {
        didSet {
            checkStateBindingRemoval?()
            checkStateBindingRemoval = nil
            
            func setState(checkbox: Checkbox, state: CheckState) {
                // Only allow mixed state if we are starting in a mixed state; otherwise we
                // use simple two-state mode
                checkbox.allowsMixedState = state == .Mixed
                checkbox.state = state.nsValue
            }
            
            if let checked = checked {
                setState(self, state: checked.value)
                checkStateBindingRemoval = checked.addChangeObserver({ [weak self] in
                    guard let weakSelf = self else { return }
                    setState(weakSelf, state: checked.value)
                })
            } else {
                setState(self, state: .Off)
            }
        }
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setButtonType(.SwitchButton)
        target = self
        action = #selector(checkboxToggled(_:))
    }

    required init?(coder: NSCoder) {
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
        checked.commit(newState)
    }
    
    override func accessibilityValue() -> AnyObject? {
        return CheckState(state).rawValue
    }
}
