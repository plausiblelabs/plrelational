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

    /// REQ-1
    /// Creates a new to-do item with the given title.
    lazy var addNewItem: ActionProperty<String> = ActionProperty { title in
        self.model.addNewItem(with: title)
    }
    
    /// REQ-2
    /// The model for the list of to-do items.
    lazy var itemsListModel: ListViewModel<RowArrayElement> = {
        return ListViewModel(
            data: self.model.items.arrayProperty(idAttr: Item.id, orderAttr: Item.status, descending: true),
            cellIdentifier: { _ in "Cell" }
        )
    }()

    /// REQ-3
    /// Returns a read/write property that resolves to the completed status for
    /// the given to-do item
    func itemCompleted(for row: Row) -> AsyncReadWriteProperty<CheckState> {
        let itemID = ItemID(row[Item.id])
        let initialValue: String? = row[Item.status].get()
        let relation = self.model.items.select(Item.id *== itemID).project(Item.status)
        return self.model.itemCompleted(relation, initialValue: initialValue)
    }

    /// REQ-4
    /// Returns a read/write property that resolves to the title for the given to-do item.
    func itemTitle(for row: Row) -> AsyncReadWriteProperty<String> {
        let itemID = ItemID(row[Item.id])
        let initialValue: String? = row[Item.title].get()
        let relation = self.model.items.select(Item.id *== itemID).project(Item.title)
        return self.model.itemTitle(relation, initialValue: initialValue)
    }
    
    /// REQ-5
    /// Returns a property that resolves to the list of tags for the given to-do item.
    func itemTags(for row: Row) -> AsyncReadableProperty<String> {
        let itemID = ItemID(row)
        return self.model.tagsString(for: itemID)
    }
    
    /// REQ-6
    /// Holds the ID of the to-do item that is selected in the list view.  This
    /// is a read/write property that is backed by UndoableDatabase, meaning that
    /// even selection changes can be undone (which admittedly is taking things
    /// to an extreme but we'll keep it like this for demonstration purposes).
    lazy var itemsListSelection: AsyncReadWriteProperty<Set<RelationValue>> = {
        return self.model.selectedItemIDs
            .undoableAllRelationValues(self.model.undoableDB, "Change Selection")
    }()
}
