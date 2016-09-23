//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import Binding
import BindableControls

class PropertiesView: BackgroundView {
    
    class Section {
        var view: NSView?
        var observerRemoval: ObserverRemoval!
        
        init<T>(property: ReadableProperty<T?>, attachView: T -> NSView) {
            
            func validate(section: Section) {
                if let view = section.view {
                    view.removeFromSuperview()
                    section.view = nil
                }
                if let model = property.value {
                    section.view = attachView(model)
                }
            }
            
            validate(self)
            
            // TODO: Handle will/didChange
            self.observerRemoval = property.signal.observe(SignalObserver(
                valueWillChange: {},
                valueChanging: { [weak self] _ in
                    guard let strongSelf = self else { return }
                    validate(strongSelf)
                },
                valueDidChange: {}
            ))
        }
    }
    
    private let model: PropertiesModel
    
    private var itemTypeLabel: TextField!
    private var nameLabel: TextField!
    private var nameField: TextField!
    private var noSelectionLabel: TextField!

    private var sections: [Section] = []
    
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
        itemTypeLabel.string <~ model.selectedItemTypesString
        itemTypeLabel.visible <~ model.itemSelected
        addSubview(itemTypeLabel)
        
        nameLabel = label(NSMakeRect(pad, 52, 50, 24))
        nameLabel.stringValue = "Name"
        nameLabel.alignment = .Right
        nameLabel.visible <~ model.itemSelected
        addSubview(nameLabel)

        nameField = field(NSMakeRect(nameLabel.frame.maxX + pad, 50, frame.width - nameLabel.frame.maxX - (pad * 2), 24))
        nameField.string <~> model.selectedItemNames
        nameField.placeholder <~ model.selectedItemNamesPlaceholder
        nameField.visible <~ model.itemSelected
        addSubview(nameField)
        
        noSelectionLabel = label(NSMakeRect(pad, 400, frame.width - (pad * 2), 24))
        noSelectionLabel.stringValue = "No Selection"
        noSelectionLabel.alignment = .Center
        noSelectionLabel.visible <~ model.itemNotSelected
        addSubview(noSelectionLabel)

        func addSection<T>(property: ReadableProperty<T?>, _ createView: T -> NSView) {
            let section = Section(property: property, attachView: { [weak self] model in
                let view = createView(model)
                if let parentView = self?.itemTypeLabel.superview {
                    parentView.addSubview(view)
                }
                return view
            })
            sections.append(section)
        }
        
        // TODO: Use an NSStackView to manage these views
        let sectionFrame = NSMakeRect(10, 100, 220, 120)
        addSection(model.textObjectProperties, { TextObjectPropertiesView(frame: sectionFrame, model: $0) })
        addSection(model.imageObjectProperties, { ImageObjectPropertiesView(frame: sectionFrame, model: $0) })
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        for section in sections {
            section.observerRemoval()
        }
    }
}
