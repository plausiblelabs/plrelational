//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelationalBinding

open class ComboBox<T: Equatable>: NSComboBox, NSComboBoxDelegate {

    public lazy var items: BindableProperty<[T]> = WriteOnlyProperty(set: { [unowned self] value, _ in
        let objects = value.map{ $0 as AnyObject }
        self.removeAllItems()
        self.addItems(withObjectValues: objects)
    })
    
    private lazy var _value: MutableValueProperty<T?> = mutableValueProperty(nil, { [unowned self] value, _ in
        self.objectValue = value as AnyObject
    })
    public var value: ReadWriteProperty<T?> { return _value }
    
    public lazy var placeholder: BindableProperty<String> = WriteOnlyProperty(set: { [unowned self] value, _ in
        self.placeholderString = value
    })
    
    private var previousCommittedValue: T?

    public override init(frame: NSRect) {
        super.init(frame: frame)
        
        delegate = self
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc open func comboBoxSelectionDidChange(_ notification: Notification) {
        if let newValue = objectValueOfSelectedItem {
            _value.change(newValue as? T, transient: false)
        }
    }
    
    open func controlTextDidBeginEditing(_ obj: Notification) {
        previousCommittedValue = objectValue as? T
    }

    open func controlTextDidEndEditing(_ obj: Notification) {
        // Note that controlTextDidBeginEditing may not be called if the user gives focus to the text field
        // but resigns first responder without typing anything, so we only commit the value if the user
        // actually typed something that differs from the previous value
        if let previousCommittedValue = previousCommittedValue {
            // TODO: Need to discard `before` snapshot if we're skipping the commit
            if let newValue = objectValue as? T {
                if newValue != previousCommittedValue {
                    _value.change(newValue, transient: false)
                }
            }
        }
        previousCommittedValue = nil
    }
}
