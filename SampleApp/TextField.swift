//
//  TextField.swift
//  Relational
//
//  Created by Chris Campbell on 5/2/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Cocoa

class TextField: NSTextField, NSTextFieldDelegate {
    
    var previousValue: String?
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        self.delegate = self
    }
    
    override func controlTextDidBeginEditing(obj: NSNotification) {
        //Swift.print("CONTROL DID BEGIN EDITING!")
        previousValue = stringValue
    }
    
    override func controlTextDidChange(notification: NSNotification) {
        //Swift.print("CONTROL DID CHANGE!")
        //string.pokeValue(stringValue, oldValue: nil)
    }
    
    override func controlTextDidEndEditing(obj: NSNotification) {
        // Note that controlTextDidBeginEditing may not be called if the user gives focus to the text field
        // but resigns first responder without typing anything, so we only commit the value if the user
        // actually typed something that differs from the previous value
        //Swift.print("CONTROL DID END EDITING!")
        if let previousValue = previousValue {
            if stringValue != previousValue {
                //string.pokeValue(stringValue, oldValue: previousValue)
            }
        }
        previousValue = nil
    }
}
