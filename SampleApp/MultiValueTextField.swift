//
//  MultiValueTextField.swift
//  Relational
//
//  Created by Chris Campbell on 5/18/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Cocoa

class MultiValueTextField: NSTextField, NSTextFieldDelegate {
    
    var strings: ValueBinding<[String]>? {
        didSet {
            stringsBindingRemoval?()
            stringsBindingRemoval = nil
            
            if let binding = strings {

                func set(field: NSTextField) {
                    let stringSet = Set(binding.value)
                    let string: String
                    let placeholder: String
                    switch stringSet.count {
                    case 0:
                        string = ""
                        // TODO: Make this configurable
                        placeholder = ""
                    case 1:
                        string = stringSet.first!
                        placeholder = ""
                    default:
                        string = ""
                        placeholder = "Multiple Values"
                    }
                    field.stringValue = string
                    field.placeholderString = placeholder
                }
                
                set(self)
                
                stringsBindingRemoval = binding.addChangeObserver({ [weak self] in
                    guard let weakSelf = self else { return }
                    // TODO: If the value becomes empty, it means that the underlying row
                    // was deleted.  In practice, the TextField may be notified of the
                    // change prior to other observers (such as the parent ListView),
                    // which means that we may see the text disappear before the list
                    // view item is removed (with a fade animation).  As a workaround,
                    // if the value is transitioning to empty, we will leave the previous
                    // text in place.
                    if binding.value.count > 0 {
                        set(weakSelf)
                    }
                })
            } else {
                stringValue = ""
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
    
    private var stringsBindingRemoval: (Void -> Void)?
    private var visibleBindingRemoval: (Void -> Void)?
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        self.delegate = self
    }
    
//    override func controlTextDidBeginEditing(obj: NSNotification) {
//        //Swift.print("CONTROL DID BEGIN EDITING!")
//        previousCommittedValue = stringValue
//        previousValue = stringValue
//    }
//    
//    override func controlTextDidChange(notification: NSNotification) {
//        //Swift.print("CONTROL DID CHANGE!")
//        if let previousValue = previousValue, bidiBinding = strings as? StringBidiBinding {
//            bidiBinding.change(newValue: stringValue, oldValue: previousValue)
//        }
//        previousValue = stringValue
//    }
//    
//    override func controlTextDidEndEditing(obj: NSNotification) {
//        // Note that controlTextDidBeginEditing may not be called if the user gives focus to the text field
//        // but resigns first responder without typing anything, so we only commit the value if the user
//        // actually typed something that differs from the previous value
//        //Swift.print("CONTROL DID END EDITING!")
//        if let previousCommittedValue = previousCommittedValue, bidiBinding = strings as? StringBidiBinding {
//            if stringValue != previousCommittedValue {
//                bidiBinding.commit(newValue: stringValue, oldValue: previousCommittedValue)
//            }
//        }
//        previousCommittedValue = nil
//        previousValue = nil
//    }
}
