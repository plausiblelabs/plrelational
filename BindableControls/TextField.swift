//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding

public class TextField: NSTextField, NSTextFieldDelegate {

    private lazy var changeHandler: ChangeHandler = ChangeHandler(
        onLock: { [unowned self] in self.enabled = false },
        onUnlock: { [unowned self] in self.enabled = true }
    )
    
    private lazy var _string: ExternalValueProperty<String> = ExternalValueProperty(
        get: { [unowned self] in
            self.stringValue ?? ""
        },
        set: { [unowned self] value, _ in
            self.stringValue = value
        },
        changeHandler: self.changeHandler
    )
    public var string: ReadWriteProperty<String> { return _string }
    
    public lazy var placeholder: BindableProperty<String> = WriteOnlyProperty(set: { [unowned self] value, _ in
        self.placeholderString = value
    })

    public lazy var visible: BindableProperty<Bool> = WriteOnlyProperty(set: { [unowned self] value, _ in
        self.hidden = !value
    })
    
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
        _string.changed(transient: true)
        previousValue = stringValue
    }
    
    public override func controlTextDidEndEditing(obj: NSNotification) {
        // Note that controlTextDidBeginEditing may not be called if the user gives focus to the text field
        // but resigns first responder without typing anything, so we only commit the value if the user
        // actually typed something that differs from the previous value
        //Swift.print("CONTROL DID END EDITING!")
        if let previousCommittedValue = previousCommittedValue {
            // TODO: Need to discard `before` snapshot if we're skipping the commit
            if stringValue != previousCommittedValue {
                _string.changed(transient: false)
            }
        }
        previousCommittedValue = nil
        previousValue = nil
    }
}
