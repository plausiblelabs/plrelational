//
//  TextField.swift
//  Relational
//
//  Created by Chris Campbell on 5/2/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Cocoa
import Binding

class TextField: NSTextField, NSTextFieldDelegate {

    private let bindings = BindingSet()

    var string: ObservableValue<String>? {
        didSet {
            bindings.observe(string, "string", { [weak self] value in
                self?.stringValue = value
            })
        }
    }

    var placeholder: ObservableValue<String>? {
        didSet {
            bindings.observe(placeholder, "placeholder", { [weak self] value in
                self?.placeholderString = value
            })
        }
    }

    var visible: ObservableValue<Bool>? {
        didSet {
            bindings.observe(visible, "visible", { [weak self] value in
                self?.hidden = !value
            })
        }
    }
    
    private var previousCommittedValue: String?
    private var previousValue: String?
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        
        self.delegate = self
    }
    
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
        if let mutableString = string as? MutableObservableValue {
            bindings.update(mutableString, newValue: stringValue, transient: true)
        }
        previousValue = stringValue
    }
    
    override func controlTextDidEndEditing(obj: NSNotification) {
        // Note that controlTextDidBeginEditing may not be called if the user gives focus to the text field
        // but resigns first responder without typing anything, so we only commit the value if the user
        // actually typed something that differs from the previous value
        //Swift.print("CONTROL DID END EDITING!")
        if let previousCommittedValue = previousCommittedValue, mutableString = string as? MutableObservableValue {
            // TODO: Need to discard `before` snapshot if we're skipping the commit
            if stringValue != previousCommittedValue {
                bindings.update(mutableString, newValue: stringValue, transient: false)
            }
        }
        previousCommittedValue = nil
        previousValue = nil
    }
}
