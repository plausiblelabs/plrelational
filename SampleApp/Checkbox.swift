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
    
    enum CheckState {
        case On
        case Off
        case Mixed
        
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
            if let checked = checked {
                self.allowsMixedState = true
                self.state = checked.value.nsValue
                checkStateBindingRemoval = checked.addChangeObserver({ [weak self] in
                    guard let weakSelf = self else { return }
                    weakSelf.allowsMixedState = true
                    weakSelf.state = checked.value.nsValue
                })
            } else {
                state = NSOffState
            }
        }
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.setButtonType(.SwitchButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func mouseDown(theEvent: NSEvent) {
        self.allowsMixedState = false
        
        switch self.checked?.value {
        case .Some(.On):
            self.checked!.commit(.Off)
        case .Some(.Off):
            self.checked!.commit(.On)
        case .Some(.Mixed):
            self.allowsMixedState = true
            self.checked!.commit(.On)
        default:
            break
        }
        performClick(self)
    }
}
