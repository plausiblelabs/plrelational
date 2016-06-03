//
//  PropertiesView.swift
//  Relational
//
//  Created by Chris Campbell on 5/5/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Cocoa
import Binding

class PropertiesView: BackgroundView {
    private let model: PropertiesModel
    
    private var itemTypeLabel: TextField!
    private var nameLabel: TextField!
    private var nameField: TextField!
    private var noSelectionLabel: TextField!

    private var textObjectPropertiesView: TextObjectPropertiesView?
    private var textObjectPropertiesObserverRemoval: ObserverRemoval?
    
    init(frame: NSRect, model: PropertiesModel) {
        self.model = model

        super.init(frame: frame)

        let pad: CGFloat = 12.0

        func label(frame: NSRect) -> TextField {
            let field = TextField(frame: frame)
            field.editable = false
            field.bezeled = false
            field.backgroundColor = NSColor.clearColor()
            field.font = NSFont.boldSystemFontOfSize(13)
            return field
        }
        
        func field(frame: NSRect) -> TextField {
            return TextField(frame: frame)
        }
        
        itemTypeLabel = label(NSMakeRect(pad, 12, frame.width - (pad * 2), 24))
        itemTypeLabel.alignment = .Center
        itemTypeLabel.string = model.selectedItemTypesString
        itemTypeLabel.visible = model.itemSelected
        addSubview(itemTypeLabel)
        
        nameLabel = label(NSMakeRect(pad, 52, 50, 24))
        nameLabel.stringValue = "Name"
        nameLabel.alignment = .Right
        nameLabel.visible = model.itemSelected
        addSubview(nameLabel)

        nameField = field(NSMakeRect(nameLabel.frame.maxX + pad, 50, frame.width - nameLabel.frame.maxX - (pad * 2), 24))
        nameField.string = model.selectedItemNames
        nameField.placeholder = model.selectedItemNamesPlaceholder
        nameField.visible = model.itemSelected
        addSubview(nameField)
        
        noSelectionLabel = label(NSMakeRect(pad, 400, frame.width - (pad * 2), 24))
        noSelectionLabel.stringValue = "No Selection"
        noSelectionLabel.alignment = .Center
        noSelectionLabel.visible = model.itemNotSelected
        addSubview(noSelectionLabel)

        updateTextSection()
        textObjectPropertiesObserverRemoval = model.textObjectProperties.addChangeObserver({ [weak self] _ in self?.updateTextSection() })
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
