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
    
    private let itemTypeLabel: TextField
    private let nameLabel: TextField
    private let nameField: TextField
    private let noSelectionLabel: TextField
    
    private let docModel: DocModel
    
    init(itemTypeLabel: TextField, nameLabel: TextField, nameField: TextField, noSelectionLabel: TextField, docModel: DocModel) {
        self.itemTypeLabel = itemTypeLabel
        self.nameLabel = nameLabel
        self.nameField = nameField
        self.noSelectionLabel = noSelectionLabel
        self.docModel = docModel
        
        itemTypeLabel.string = docModel.selectedItemTypesString
        itemTypeLabel.visible = docModel.itemSelected

        nameLabel.visible = docModel.itemSelected

        nameField.string = docModel.selectedItemNames
        nameField.placeholder = docModel.selectedItemNamesPlaceholder
        nameField.visible = docModel.itemSelected

        noSelectionLabel.visible = docModel.itemNotSelected
    }
}
