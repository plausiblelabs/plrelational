//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelational
import PLRelationalBinding

class DetailViewModel {

    // completed
    // text field
    // assign tag
    // tag list
    // added on (date)
    // delete button
    
    private let model: Model
    
    init(model: Model) {
        self.model = model
    }
    
    lazy var itemText: AsyncReadWriteProperty<String> = {
        let textRelation = self.model.selectedItems.project(Item.text)
        return self.model.itemText(textRelation, initialValue: nil)
    }()
}
