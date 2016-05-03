//
//  TextField.swift
//  Relational
//
//  Created by Chris Campbell on 5/2/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Cocoa

class TextField: NSTextField, NSTextFieldDelegate {

    var string: BidiBinding<String>? {
        didSet {
            if let string = string {
                // TODO: Observe changes
                stringValue = string.get().ok!.get()!
            }
        }
    }
    
    private var previousCommittedValue: String?
    private var previousValue: String?
    
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
        if let previousValue = previousValue {
            string?.change(newValue: stringValue, oldValue: previousValue)
        }
        previousValue = stringValue
    }
    
    override func controlTextDidEndEditing(obj: NSNotification) {
        // Note that controlTextDidBeginEditing may not be called if the user gives focus to the text field
        // but resigns first responder without typing anything, so we only commit the value if the user
        // actually typed something that differs from the previous value
        //Swift.print("CONTROL DID END EDITING!")
        if let previousCommittedValue = previousCommittedValue {
            if stringValue != previousCommittedValue {
                string?.commit(newValue: stringValue, oldValue: previousCommittedValue)
            }
        }
        previousCommittedValue = nil
        previousValue = nil
    }
}
