//
//  TextObjectPropertiesView.swift
//  Relational
//
//  Created by Chris Campbell on 5/30/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Cocoa

class TextObjectPropertiesView: BackgroundView {

    var editableCheckbox: Checkbox!
    var hintField: TextField!
    var fontPopupButton: PopUpButton!

    init(frame: NSRect, model: TextObjectPropertiesModel) {
        super.init(frame: frame)
        
        editableCheckbox = Checkbox(frame: NSMakeRect(10, 10, 120, 24), checkState: false)
        editableCheckbox.checked = model.editable
        addSubview(editableCheckbox)
        
        hintField = TextField()
        hintField.frame = NSMakeRect(10, 46, 120, 24)
        hintField.string = model.hint
        hintField.placeholder = model.hintPlaceholder
        addSubview(hintField)
        
        fontPopupButton = PopUpButton(frame: NSMakeRect(10, 80, 120, 24), pullsDown: false)
        fontPopupButton.titles = model.availableFonts
        fontPopupButton.placeholderTitle = model.fontPlaceholder
        fontPopupButton.selectedTitle = model.font
        addSubview(fontPopupButton)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
