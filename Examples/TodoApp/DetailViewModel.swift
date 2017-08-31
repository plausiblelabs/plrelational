//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelational
import PLRelationalBinding

class DetailViewModel {

    private let model: Model
    
    init(model: Model) {
        self.model = model
    }
    
    /// The item's title.  This is a read/write property that is backed by UndoableDatabase, so any changes
    /// made to it in the text field can be rolled back by the user.
    lazy var itemTitle: AsyncReadWriteProperty<String> = {
        let textRelation = self.model.selectedItems.project(Item.title)
        return self.model.itemTitle(textRelation, initialValue: nil)
    }()
    
    /// The text that appears in the "Created on <date>" label.  This demonstrates the use of `map` to
    /// convert the raw timestamp string (as stored in the relation) to a display-friendly string.
    lazy var createdOn: AsyncReadableProperty<String> = {
        return self.model.selectedItems
            .project(Item.created)
            .oneStringOrNil()
            .property()
            .map{
                let date = $0.map(displayString) ?? "Unknown"
                return "Created on \(date)"
            }
    }()
    
    /// Deletes the selected item.  This demonstrates the use of `ActionProperty` to expose an imperative
    /// (side effect producing) action as a property that can easily be bound to a `Button`.
    lazy var deleteItem: ActionProperty<()> = ActionProperty { _ in 
        self.model.deleteSelectedItem()
    }
}
