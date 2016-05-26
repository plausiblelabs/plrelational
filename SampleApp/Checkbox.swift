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
        
        func get() -> Int {
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

    private var checkStateBindingRemoval: ObserverRemoval?
    
    var checked: ValueBinding<CheckState> {
        didSet {
            checkStateBindingRemoval?()
            checkStateBindingRemoval = nil
            checkStateBindingRemoval = checked.addChangeObserver({ [weak self] in
                guard let weakSelf = self else { return }
                weakSelf.state = self!.checked.value.get()
            })
        }
    }
    
    init(frame frameRect: NSRect, checkState: Bool?) {
        self.checked = ValueBinding<CheckState>(initialValue: CheckState(checkState))
        
        super.init(frame: frameRect)
        
        self.setButtonType(.SwitchButton)
//        self.allowsMixedState = true
        
        // TODO: handle mixed state. if self.allowsMixedState is set to 'true', the button toggles through a three-state
        //       cycle on user interaction.
        
        self.state = self.checked.value.get()
    }
    
    // ???
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}