//
//  PropertiesView.swift
//  Relational
//
//  Created by Chris Campbell on 5/5/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Cocoa
import Binding

// Note: Normally this would be an NSView subclass, but for the sake of expedience we defined the UI in
// a single Document.xib, so this class simply manages a subset of views defined in that xib.
class PropertiesView {
    private let model: PropertiesModel
    
    private let itemTypeLabel: TextField
    private let nameLabel: TextField
    private let nameField: TextField
    private let noSelectionLabel: TextField

    private var textObjectPropertiesView: TextObjectPropertiesView?
    private var textObjectPropertiesObserverRemoval: ObserverRemoval?
    
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
        textObjectPropertiesObserverRemoval = model.textObjectProperties.addChangeObserver({ [weak self] _ in self?.updateTextSection() })
    }
    
    deinit {
        textObjectPropertiesObserverRemoval?()
    }
    
    private func removeTextSection() {
        guard let view = textObjectPropertiesView else { return }
        view.removeFromSuperview()
        textObjectPropertiesView = nil
    }
    
    private func addTextSection(model: TextObjectPropertiesModel) {
        let view = TextObjectPropertiesView(frame: NSMakeRect(10, 100, 220, 120), model: model)
        view.backgroundColor = NSColor.blueColor()
        textObjectPropertiesView = view
        
        let parentView = itemTypeLabel.superview!
        parentView.addSubview(view)
    }
    
    private func updateTextSection() {
        removeTextSection()
        if let model = model.textObjectProperties.value {
            addTextSection(model)
        }
    }
}
