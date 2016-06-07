//
//  ImageObjectPropertiesView.swift
//  Relational
//
//  Created by Chris Campbell on 6/7/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Cocoa

class ImageObjectPropertiesView: BackgroundView {
    
    var editableCheckbox: Checkbox!
    
    init(frame: NSRect, model: ImageObjectPropertiesModel) {
        super.init(frame: frame)
        
        editableCheckbox = Checkbox(frame: NSMakeRect(10, 10, 120, 24))
        editableCheckbox.title = "Editable"
        editableCheckbox.checked = model.editable
        addSubview(editableCheckbox)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
