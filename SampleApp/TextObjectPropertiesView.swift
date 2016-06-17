//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding
import BindableControls

class TextObjectPropertiesView: BackgroundView {

    var editableCheckbox: Checkbox!
    var hintField: TextField!
    var fontPopupButton: PopUpButton<String>!

    init(frame: NSRect, model: TextObjectPropertiesModel) {
        super.init(frame: frame)
        
        editableCheckbox = Checkbox(frame: NSMakeRect(10, 10, 120, 24))
        editableCheckbox.title = "Editable"
        editableCheckbox.checked = model.editable
        addSubview(editableCheckbox)
        
        hintField = TextField()
        hintField.frame = NSMakeRect(10, 46, 120, 24)
        hintField.string <~ model.hint
        hintField.placeholder <~ model.hintPlaceholder
        addSubview(hintField)
        
        fontPopupButton = PopUpButton(frame: NSMakeRect(10, 80, 120, 24), pullsDown: false)
        fontPopupButton.items <~ ObservableValue.constant(model.availableFonts.map{ titledMenuItem($0) })
        fontPopupButton.defaultItemContent = MenuItemContent(object: "Default", title: model.fontPlaceholder)
        fontPopupButton.selectedObject = model.font
        addSubview(fontPopupButton)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
