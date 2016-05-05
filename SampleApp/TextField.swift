//
//  TextField.swift
//  Relational
//
//  Created by Chris Campbell on 5/2/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Cocoa

class TextField: NSTextField, NSTextFieldDelegate {

    var string: ValueBinding<String?>? {
        didSet {
            stringBindingRemoval?()
            stringBindingRemoval = nil
            if let string = string {
                stringValue = string.value ?? ""
                stringBindingRemoval = string.addChangeObserver({ [weak self] in
                    guard let weakSelf = self else { return }
                    if weakSelf.selfInitiatedChange { return }
                    //Swift.print("UPDATING TextField.stringValue: \(string.value)")
                    weakSelf.stringValue = string.value ?? ""
                })
            } else {
                stringValue = ""
            }
        }
    }
    
    var visible: ValueBinding<Bool>? {
        didSet {
            visibleBindingRemoval?()
            visibleBindingRemoval = nil
            if let visible = visible {
                hidden = !visible.value
                visibleBindingRemoval = visible.addChangeObserver({ [weak self] in self?.hidden = !visible.value })
            } else {
                hidden = false
            }
        }
    }
    
    private var previousCommittedValue: String?
    private var previousValue: String?
    
    private var stringBindingRemoval: (Void -> Void)?
    private var selfInitiatedChange = false
    private var visibleBindingRemoval: (Void -> Void)?
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        self.delegate = self
    }
    
    override func controlTextDidBeginEditing(obj: NSNotification) {
        //Swift.print("CONTROL DID BEGIN EDITING!")
        previousCommittedValue = stringValue
        previousValue = stringValue
    }
    
    override func controlTextDidChange(notification: NSNotification) {
        //Swift.print("CONTROL DID CHANGE!")
        //string.pokeValue(stringValue, oldValue: nil)
        if let previousValue = previousValue, bidiBinding = string as? StringBidiBinding {
            selfInitiatedChange = true
            bidiBinding.change(newValue: stringValue, oldValue: previousValue)
            selfInitiatedChange = false
        }
        previousValue = stringValue
    }
    
    override func controlTextDidEndEditing(obj: NSNotification) {
        // Note that controlTextDidBeginEditing may not be called if the user gives focus to the text field
        // but resigns first responder without typing anything, so we only commit the value if the user
        // actually typed something that differs from the previous value
        //Swift.print("CONTROL DID END EDITING!")
        if let previousCommittedValue = previousCommittedValue, bidiBinding = string as? StringBidiBinding {
            if stringValue != previousCommittedValue {
                selfInitiatedChange = true
                bidiBinding.commit(newValue: stringValue, oldValue: previousCommittedValue)
                selfInitiatedChange = false
            }
        }
        previousCommittedValue = nil
        previousValue = nil
    }
}
