//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding

public class TextField: NSTextField, NSTextFieldDelegate {

    private let bindings = BindingSet()

    public var string: ObservableValue<String>? {
        didSet {
            bindings.observe(string, "string", { [weak self] value in
                self?.stringValue = value
            })
        }
    }

    public lazy var placeholder: Property<String> = Property { [weak self] value in
        self?.placeholderString = value
    }

    public lazy var visible: Property<Bool> = Property { [weak self] value in
        self?.hidden = !value
    }
    
    private var previousCommittedValue: String?
    private var previousValue: String?
    
    public override init(frame: NSRect) {
        super.init(frame: frame)
        
        self.delegate = self
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        self.delegate = self
    }
    
    public override func controlTextDidBeginEditing(obj: NSNotification) {
        //Swift.print("CONTROL DID BEGIN EDITING!")
        previousCommittedValue = stringValue
        previousValue = stringValue
    }
    
    public override func controlTextDidChange(notification: NSNotification) {
        //Swift.print("CONTROL DID CHANGE!")
        if let mutableString = string as? MutableObservableValue {
            bindings.update(mutableString, newValue: stringValue, transient: true)
        }
        previousValue = stringValue
    }
    
    public override func controlTextDidEndEditing(obj: NSNotification) {
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
