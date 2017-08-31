//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelational
import PLRelationalBinding
import PLBindableControls

class ChecklistViewModel {
    
    private let model: Model
    
    init(model: Model) {
        self.model = model
    }
    
    /// The model for the list of to-do items.
    lazy var itemsListModel: ListViewModel<RowArrayElement> = {
        return ListViewModel(
            data: self.model.items.arrayProperty(idAttr: Item.id, orderAttr: Item.status),
            contextMenu: nil,
            move: nil,
            cellIdentifier: { _ in "Cell" }
        )
    }()
    
    /// Returns a read/write property that resolves to the title for the given to-do item.
    func itemTitle(for row: Row) -> AsyncReadWriteProperty<String> {
        let itemID = row[Item.id]
        let initialValue: String? = row[Item.title].get()
        let textRelation = self.model.items.select(Item.id *== itemID).project(Item.title)
        return self.model.itemTitle(textRelation, initialValue: initialValue)
    }
    
    /// Returns a property that resolves to the list of tags for the given to-do item.
    func itemTags(for row: Row) -> AsyncReadableProperty<String> {
        return self.model.tagsString(for: row[Item.id].get()!)
    }
    
    /// Holds the ID of the to-do item that is selected in the list view.  This
    /// is a read/write property that is backed by UndoableDatabase, meaning that
    /// even selection changes can be undone (which admittedly is taking things
    /// to an extreme but we'll keep it like this for demonstration purposes).
    lazy var itemsListSelection: AsyncReadWriteProperty<Set<RelationValue>> = {
        return self.model.undoableBidiProperty(
            action: "Change Selection",
            signal: self.model.selectedItemIDs.allRelationValues(),
            update: { self.model.selectedItemIDs.asyncReplaceValues(Array($0)) }
        )
    }()
}
