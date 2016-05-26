//
//  Checkbox.swift
//  Relational
//
//  Created by Terri Kramer on 5/25/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Cocoa

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
    }
    
    var checked: ValueBinding<CheckState> {
        didSet {
            switch checked.value {
            case .On:
                self.state = NSOnState
            case .Off:
                self.state = NSOffState
            case .Mixed:
                self.state = NSMixedState
            }
        }
    }
    
    init(frame frameRect: NSRect, checkState: CheckState) {
        self.checked = ValueBinding<CheckState>(initialValue: checkState)
        
        super.init(frame: frameRect)
        
        self.setButtonType(.SwitchButton)
    }
    
    // ???
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
