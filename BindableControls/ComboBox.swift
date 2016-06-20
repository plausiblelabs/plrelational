//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding

public class ComboBox<T: Equatable>: NSComboBox, NSComboBoxDelegate {

    public lazy var items: Property<[T]> = Property { [weak self] value, _ in
        let objects = value.map{ $0 as! AnyObject }
        self?.addItemsWithObjectValues(objects)
    }
    
    private lazy var _value: ValueBidiProperty<T?> = ValueBidiProperty(
        initialValue: nil,
        didSet: { [unowned self] value, _ in
            self.objectValue = value as? AnyObject
        }
    )
    public var value: BidiProperty<T?> { return _value }
    
    public lazy var placeholder: Property<String> = Property { [unowned self] value, _ in
        self.placeholderString = value
    }
    
    private var previousCommittedValue: T?

    public override init(frame: NSRect) {
        super.init(frame: frame)
        
        delegate = self
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc public func comboBoxSelectionDidChange(notification: NSNotification) {
        if let newValue = objectValueOfSelectedItem {
            _value.change(newValue: newValue as? T, transient: false)
        }
    }
    
    public override func controlTextDidBeginEditing(obj: NSNotification) {
        previousCommittedValue = objectValue as? T
    }

    public override func controlTextDidEndEditing(obj: NSNotification) {
        // Note that controlTextDidBeginEditing may not be called if the user gives focus to the text field
        // but resigns first responder without typing anything, so we only commit the value if the user
        // actually typed something that differs from the previous value
        if let previousCommittedValue = previousCommittedValue {
            // TODO: Need to discard `before` snapshot if we're skipping the commit
            if let newValue = objectValue as? T {
                if newValue != previousCommittedValue {
                    _value.change(newValue: newValue, transient: false)
                }
            }
        }
        previousCommittedValue = nil
    }
}
