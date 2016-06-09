//
//  ComboBox.swift
//  Relational
//
//  Created by Chris Campbell on 6/8/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Cocoa
import Binding

class ComboBox<T>: NSComboBox, NSComboBoxDelegate {

    private let bindings = BindingSet()
    
    var items: ValueBinding<[T]>? {
        didSet {
            bindings.register("items", items, { [weak self] value in
                let objects = value.map{ $0 as! AnyObject }
                self?.addItemsWithObjectValues(objects)
            })
        }
    }
    
    var value: BidiValueBinding<T>? {
        didSet {
            bindings.register("value", value, { [weak self] value in
                self?.objectValue = value as? AnyObject
            })
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        
        delegate = self
        target = self
        action = #selector(textChanged(_:))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func comboBoxSelectionDidChange(notification: NSNotification) {
        if let newValue = objectValueOfSelectedItem {
            value?.commit(newValue as! T)
        }
    }
    
    override func controlTextDidChange(notification: NSNotification) {
        //Swift.print("CONTROL DID CHANGE!")
        if let newValue = objectValue as? T {
            value?.update(newValue)
        }
    }
    
    // TODO: Should probably just use controlTextDidEndEditing here instead
    @objc func textChanged(sender: NSComboBox) {
        if let newValue = objectValue as? T {
            value?.commit(newValue)
        }
    }
}
