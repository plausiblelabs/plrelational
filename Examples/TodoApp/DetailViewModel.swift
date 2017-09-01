//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelational
import PLRelationalBinding
import PLBindableControls

class DetailViewModel {

    private let model: Model
    
    /// The selected item ID, cached in this property for easy access.
    private let itemID: AsyncReadableProperty<ItemID?>
    
    init(model: Model) {
        self.model = model
        
        self.itemID = self.model.selectedItemIDs
            .oneStringOrNil()
            .property()
            .map{ $0.map(ItemID.init) }
        self.itemID.start()
    }

    /// The completed status of the item.
    lazy var itemCompleted: AsyncReadWriteProperty<CheckState> = {
        let relation = self.model.selectedItems.project(Item.status)
        return self.model.itemCompleted(relation, initialValue: nil)
    }()

    /// The item's title.  This is a read/write property that is backed by UndoableDatabase, so any changes
    /// made to it in the text field can be rolled back by the user.
    lazy var itemTitle: AsyncReadWriteProperty<String> = {
        let titleRelation = self.model.selectedItems.project(Item.title)
        return self.model.itemTitle(titleRelation, initialValue: nil)
    }()

    /// The item's notes.
    lazy var itemNotes: AsyncReadWriteProperty<String> = {
        return self.model.selectedItemNotes
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
    
    // MARK: - Tags

    /// The tags associated with the selected to-do item, sorted by name.
    private lazy var itemTags: ArrayProperty<RowArrayElement> = {
        return self.model.tagsForSelectedItem
            .arrayProperty(idAttr: Tag.id, orderAttr: Tag.name)
    }()

    /// The tags that are available (i.e., not already applied) for the selected to-do
    /// item, sorted by name.  We use `fullArray` so that the entire array is delivered
    /// any time there is a change; this helps to make it compatible with
    /// the `EphemeralComboBox` class.
    lazy var availableTags: AsyncReadableProperty<[RowArrayElement]> = {
        return self.model.availableTagsForSelectedItem
            .arrayProperty(idAttr: Tag.id, orderAttr: Tag.name)
            .fullArray()
    }()

    /// The model for the tags list, i.e., the tags that have been applied to the
    /// selected to-do item.
    lazy var tagsListViewModel: ListViewModel<RowArrayElement> = {
        return ListViewModel(
            data: self.itemTags,
            contextMenu: nil,
            move: nil,
            cellIdentifier: { _ in "Cell" }
        )
    }()
    
    /// Returns a read/write property that resolves to the name for the given tag.
    func tagName(for row: Row) -> AsyncReadWriteProperty<String> {
        let tagID = TagID(row)
        let name: String? = row[Tag.name].get()
        return self.model.tagName(for: tagID, initialValue: name)
    }
    
    /// Holds the ID of the tag that is selected in the tags list view.
    lazy var selectedTagID: ReadWriteProperty<Set<RelationValue>> = {
        return mutableValueProperty(Set())
    }()
    
    private func addExistingTagToSelected(tagID: TagID) {
        self.model.addExistingTag(tagID, to: itemID.value!!)
    }

    /// Adds an existing tag to the selected to-do item.
    lazy var addExistingTagToSelectedItem: ActionProperty<RelationValue> = ActionProperty { tagID in
        self.addExistingTagToSelected(tagID: TagID(tagID))
    }

    private func addNewTagToSelected(with name: String) {
        // See if a tag already exists with the given name
        let itemID = self.itemID.value!!
        let existingIndex = model.allTags.value?.index(where: {
            let rowName: String = $0.data[Tag.name].get()!
            return name == rowName
        })
        if let index = existingIndex {
            // A tag already exists with the given name, so apply that tag rather than creating a new one
            let elem = model.allTags.value![index]
            let tagID = TagID(elem.data)
            model.addExistingTag(tagID, to: itemID)
        } else {
            // No tag exists with that name, so create a new tag and apply it to this item
            model.addNewTag(named: name, to: itemID)
        }
    }
    
    /// Creates a new tag of the given name and adds it to the selected to-do item.
    lazy var addNewTagToSelectedItem: ActionProperty<String> = ActionProperty { name in
        self.addNewTagToSelected(with: name)
    }
}
