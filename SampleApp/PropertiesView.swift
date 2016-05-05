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
    
    let itemTypeLabel: TextField
    let nameLabel: TextField
    let nameField: TextField
    let noSelectionLabel: TextField
    
    let docModel: DocModel
    
    init(itemTypeLabel: TextField, nameLabel: TextField, nameField: TextField, noSelectionLabel: TextField, docModel: DocModel) {
        self.itemTypeLabel = itemTypeLabel
        self.nameLabel = nameLabel
        self.nameField = nameField
        self.noSelectionLabel = noSelectionLabel
        self.docModel = docModel
        
//        itemTypeLabel.string = docModel.selectedItemType
        itemTypeLabel.visible = docModel.itemSelected

        nameLabel.visible = docModel.itemSelected

//        nameField.string = docModel.selectedItemName
        nameField.visible = docModel.itemSelected

        noSelectionLabel.visible = docModel.itemNotSelected
    }
}
