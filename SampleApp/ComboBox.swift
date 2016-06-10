//
//  ComboBox.swift
//  Relational
//
//  Created by Chris Campbell on 6/8/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Cocoa
import Binding

class ComboBox<T: Equatable>: NSComboBox, NSComboBoxDelegate {

    private let bindings = BindingSet()
    
    var items: ValueBinding<[T]>? {
        didSet {
            bindings.register("items", items, { [weak self] value in
                let objects = value.map{ $0 as! AnyObject }
                self?.addItemsWithObjectValues(objects)
            })
        }
    }
    
    var value: BidiValueBinding<T?>? {
        didSet {
            bindings.register("value", value, { [weak self] value in
                guard let weakSelf = self else { return }
                if weakSelf.selfInitiatedValueChange { return }
                weakSelf.objectValue = value as? AnyObject
            })
        }
    }
    
    private var previousCommittedValue: T?
    private var selfInitiatedValueChange = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        
        delegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func comboBoxSelectionDidChange(notification: NSNotification) {
        if let newValue = objectValueOfSelectedItem {
            selfInitiatedValueChange = true
            value?.commit(newValue as? T)
            selfInitiatedValueChange = false
        }
    }
    
    override func controlTextDidBeginEditing(obj: NSNotification) {
        previousCommittedValue = objectValue as? T
    }

    override func controlTextDidEndEditing(obj: NSNotification) {
        // Note that controlTextDidBeginEditing may not be called if the user gives focus to the text field
        // but resigns first responder without typing anything, so we only commit the value if the user
        // actually typed something that differs from the previous value
        if let previousCommittedValue = previousCommittedValue, binding = value {
            // TODO: Need to discard `before` snapshot if we're skipping the commit
            if let newValue = objectValue as? T {
                if newValue != previousCommittedValue {
                    selfInitiatedValueChange = true
                    binding.commit(newValue)
                    selfInitiatedValueChange = false
                }
            }
        }
        previousCommittedValue = nil
    }
}
