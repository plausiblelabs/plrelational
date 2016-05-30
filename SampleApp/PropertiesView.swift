//
//  PropertiesView.swift
//  Relational
//
//  Created by Chris Campbell on 5/5/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Cocoa

// Note: Normally this would be an NSView subclass, but for the sake of expedience we defined the UI in
// a single Document.xib, so this class simply manages a subset of views defined in that xib.
class PropertiesView {
    
    struct TextSection {
        let view: NSView
        let editableCheckbox: Checkbox
        let hintField: TextField
        let fontPopupButton: PopUpButton
    }

    private let model: PropertiesModel
    
    private let itemTypeLabel: TextField
    private let nameLabel: TextField
    private let nameField: TextField
    private let noSelectionLabel: TextField

    private var textSection: TextSection?
    private var textObjectPropsObserverRemoval: ObserverRemoval?
    
    init(model: PropertiesModel, itemTypeLabel: TextField, nameLabel: TextField, nameField: TextField, noSelectionLabel: TextField) {
        self.model = model
        self.itemTypeLabel = itemTypeLabel
        self.nameLabel = nameLabel
        self.nameField = nameField
        self.noSelectionLabel = noSelectionLabel
        
        itemTypeLabel.string = model.selectedItemTypesString
        itemTypeLabel.visible = model.itemSelected

        nameLabel.visible = model.itemSelected

        nameField.string = model.selectedItemNames
        nameField.placeholder = model.selectedItemNamesPlaceholder
        nameField.visible = model.itemSelected

        noSelectionLabel.visible = model.itemNotSelected

        updateTextSection()
        textObjectPropsObserverRemoval = model.textObjectProperties.addChangeObserver({ [weak self] _ in self?.updateTextSection() })
    }
    
    private func removeTextSection() {
        guard let section = textSection else { return }

        section.view.removeFromSuperview()
        textSection = nil
    }
    
    private func addTextSection(model: TextObjectPropertiesModel) {
        // XXX
        let parentView = itemTypeLabel.superview!
        let bgView = BackgroundView(frame: NSMakeRect(10, 100, 220, 120))
        bgView.backgroundColor = NSColor.blueColor()
        
        let editableCheckbox = Checkbox(frame: NSMakeRect(10, 10, 120, 24), checkState: false)
        editableCheckbox.checked = model.editable
        bgView.addSubview(editableCheckbox)
        
        let hintField = TextField()
        hintField.frame = NSMakeRect(10, 46, 120, 24)
        hintField.string = model.hint
        hintField.placeholder = model.hintPlaceholder
        bgView.addSubview(hintField)

        let fontPopupButton = PopUpButton(frame: NSMakeRect(10, 80, 120, 24), pullsDown: false)
        fontPopupButton.titles = model.availableFonts
        fontPopupButton.placeholderTitle = model.fontPlaceholder
        fontPopupButton.selectedTitle = model.font
        bgView.addSubview(fontPopupButton)
        
        parentView.addSubview(bgView)
        textSection = TextSection(
            view: bgView,
            editableCheckbox: editableCheckbox,
            hintField: hintField,
            fontPopupButton: fontPopupButton
        )
    }
    
    private func updateTextSection() {
        removeTextSection()
        if let model = model.textObjectProperties.value {
            addTextSection(model)
        }
    }
}
