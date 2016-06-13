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
    
    var items: ObservableValue<[T]>? {
        didSet {
            bindings.observe(items, "items", { [weak self] value in
                let objects = value.map{ $0 as! AnyObject }
                self?.addItemsWithObjectValues(objects)
            })
        }
    }
    
    var value: MutableObservableValue<T?>? {
        didSet {
            bindings.observe(value, "value", { [weak self] value in
                self?.objectValue = value as? AnyObject
            })
        }
    }
    
    private var previousCommittedValue: T?

    override init(frame: NSRect) {
        super.init(frame: frame)
        
        delegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func comboBoxSelectionDidChange(notification: NSNotification) {
        if let newValue = objectValueOfSelectedItem {
            bindings.update(value, newValue: newValue as? T)
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
                    bindings.update(binding, newValue: newValue)
                }
            }
        }
        previousCommittedValue = nil
    }
}
