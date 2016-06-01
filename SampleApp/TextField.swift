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

    var string: ValueBinding<String>? {
        didSet {
            stringBindingRemoval?()
            stringBindingRemoval = nil
            if let string = string {
                stringValue = string.value
                stringBindingRemoval = string.addChangeObserver({ [weak self] in
                    guard let weakSelf = self else { return }
                    // TODO: If the value becomes nil, it means that the underlying row
                    // was deleted.  In practice, the TextField may be notified of the
                    // change prior to other observers (such as the parent ListView),
                    // which means that we may see the text disappear before the list
                    // view item is removed (with a fade animation).  As a workaround,
                    // if the value is transitioning to nil, we will leave the previous
                    // text in place.
                    // XXX: The above no longer applies, since the string is no longer an optional type
//                    if let value = string.value {
                        weakSelf.stringValue = string.value
//                    }
                })
            } else {
                stringValue = ""
            }
        }
    }

    var placeholder: ValueBinding<String>? {
        didSet {
            placeholderBindingRemoval?()
            placeholderBindingRemoval = nil
            if let placeholder = placeholder {
                placeholderString = placeholder.value
                placeholderBindingRemoval = placeholder.addChangeObserver({ [weak self] in
                    guard let weakSelf = self else { return }
                    weakSelf.placeholderString = placeholder.value
                })
            } else {
                placeholderString = ""
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
    
    private var stringBindingRemoval: ObserverRemoval?
    private var placeholderBindingRemoval: ObserverRemoval?
    private var visibleBindingRemoval: ObserverRemoval?
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        
        self.delegate = self
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        self.delegate = self
    }
    
    deinit {
        stringBindingRemoval?()
        placeholderBindingRemoval?()
        visibleBindingRemoval?()
    }
    
    override func controlTextDidBeginEditing(obj: NSNotification) {
        //Swift.print("CONTROL DID BEGIN EDITING!")
        previousCommittedValue = stringValue
        previousValue = stringValue
    }
    
    override func controlTextDidChange(notification: NSNotification) {
        //Swift.print("CONTROL DID CHANGE!")
        if let bidiBinding = string as? BidiValueBinding {
            bidiBinding.update(stringValue)
        }
        previousValue = stringValue
    }
    
    override func controlTextDidEndEditing(obj: NSNotification) {
        // Note that controlTextDidBeginEditing may not be called if the user gives focus to the text field
        // but resigns first responder without typing anything, so we only commit the value if the user
        // actually typed something that differs from the previous value
        //Swift.print("CONTROL DID END EDITING!")
        if let previousCommittedValue = previousCommittedValue, bidiBinding = string as? BidiValueBinding {
            // TODO: Need to discard `before` snapshot if we're skipping the commit
            if stringValue != previousCommittedValue {
                bidiBinding.commit(stringValue)
            }
        }
        previousCommittedValue = nil
        previousValue = nil
    }
}
