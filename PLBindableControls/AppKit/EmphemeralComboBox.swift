//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelational
import PLRelationalBinding

/// A variant of `ComboBox` that clears the text field whenever an item is selected or new text
/// is committed.  Unlike `ComboBox`, this class is not generic and only supports string values.
open class EphemeralComboBox: NSComboBox, NSComboBoxDelegate {
    
    private lazy var _items: MutableValueProperty<[RowArrayElement]> = mutableValueProperty([], { value, _ in
        let stringValues = value.map{ (elem: RowArrayElement) -> String in
            // TODO: Make this attribute configurable
            return elem.data["name"].get()!
        }
        self.removeAllItems()
        self.addItems(withObjectValues: stringValues)
    })
    public var items: BindableProperty<[RowArrayElement]> { return _items }
    
    private let _selectedItemID = SourceSignal<RelationValue>()
    public var selectedItemID: Signal<RelationValue> { return _selectedItemID }
    
    private let _committedString = SourceSignal<String>()
    public var committedString: Signal<String> { return _committedString }
    
    public lazy var placeholder: BindableProperty<String> = WriteOnlyProperty(set: { value, _ in
        self.placeholderString = value
    })
    
    private var poppedUp = false
    
    public override init(frame: NSRect) {
        super.init(frame: frame)
        
        delegate = self
        target = self
        action = #selector(stringCommitted(_:))
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        delegate = self
        target = self
        action = #selector(stringCommitted(_:))
    }
    
    @objc open func comboBoxWillPopUp(_ notification: Notification) {
        poppedUp = true
    }
    
    @objc open func comboBoxWillDismiss(_ notification: Notification) {
        if poppedUp && indexOfSelectedItem >= 0 {
            // An item was selected by clicking a popup item or by pressing enter after the item
            // was highlighted.  We immediately notify and deselect the item to prevent it from
            // appearing in the text field.
            notifyItemSelected(at: indexOfSelectedItem)
        }
        poppedUp = false
    }
    
    private func notifyItemSelected(at index: Int) {
        let element = _items.value[index]
        _selectedItemID.notifyValueChanging(element.id)
        deselectItem(at: index)
    }
    
    func stringCommitted(_ sender: NSComboBox) {
        if self.stringValue.isEmpty {
            // Nothing to do when the string is empty
            return
        }
        
        // Send the committed string value
        self._committedString.notifyValueChanging(self.stringValue)
        
        // Clear the text field
        if self.indexOfSelectedItem >= 0 {
            self.deselectItem(at: self.indexOfSelectedItem)
        }
        self.stringValue = ""
    }
}
