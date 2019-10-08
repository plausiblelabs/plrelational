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
        
        // TODO: Docs
        self.itemID = self.model.selectedItemIDs
            .oneStringOrNil()
            .property()
            .map{ $0.map(ItemID.init) }
        self.itemID.start()
    }

    // MARK: - Checkbox and Title
    
    /// REQ-7
    /// The completed status of the item.
    lazy var itemCompleted: AsyncReadWriteProperty<CheckState> = {
        let relation = self.model.selectedItems.project(Item.status)
        return self.model.itemCompleted(relation, initialValue: nil)
    }()

    /// REQ-8
    /// The item's title.  This is a read/write property that is backed
    /// by UndoableDatabase, so any changes made to it in the text field
    /// can be rolled back by the user.
    lazy var itemTitle: AsyncReadWriteProperty<String> = {
        let titleRelation = self.model.selectedItems.project(Item.title)
        return self.model.itemTitle(titleRelation, initialValue: nil)
    }()

    // MARK: - Tags

    /// REQ-9
    /// The tags that are available (i.e., not already applied) for the selected
    /// to-do item, sorted by name.  We use `fullArray` so that the entire array
    /// is delivered any time there is a change; this helps to make it
    /// compatible with the `EphemeralComboBox` class.
    lazy var availableTags: AsyncReadableProperty<[RowArrayElement]> = {
        return self.model.availableTagsForSelectedItem
            .arrayProperty(idAttr: Tag.id, orderAttr: Tag.name)
            .fullArray()
    }()
    
    /// REQ-9
    /// Adds an existing tag to the selected to-do item.
    lazy var addExistingTagToSelectedItem: ActionProperty<RelationValue> = ActionProperty { tagID in
        self.model.addExistingTag(TagID(tagID), to: self.itemID.value!!)
    }
    
    /// REQ-9
    /// Creates a new tag of the given name and adds it to the selected to-do item.
    lazy var addNewTagToSelectedItem: ActionProperty<String> = ActionProperty { name in
        // See if a tag already exists with the given name
        let itemID = self.itemID.value!!
        let existingIndex = self.model.allTags.value?.firstIndex(where: {
            let rowName: String = $0.data[Tag.name].get()!
            return name == rowName
        })
        if let index = existingIndex {
            // A tag already exists with the given name, so apply that tag
            // rather than creating a new one
            let elem = self.model.allTags.value![index]
            let tagID = TagID(elem.data)
            self.model.addExistingTag(tagID, to: itemID)
        } else {
            // No tag exists with that name, so create a new tag and apply
            // it to this item
            self.model.addNewTag(named: name, to: itemID)
        }
    }
    
    /// REQ-10
    /// The tags associated with the selected to-do item, sorted by name.
    private lazy var itemTags: ArrayProperty<RowArrayElement> = {
        return self.model.tagsForSelectedItem
            .arrayProperty(idAttr: Tag.id, orderAttr: Tag.name)
    }()
    
    /// REQ-10
    /// The model for the tags list, i.e., the tags that have been applied to the
    /// selected to-do item.
    lazy var tagsListViewModel: ListViewModel<RowArrayElement> = {
        return ListViewModel(
            data: self.itemTags,
            cellIdentifier: { _ in "Cell" }
        )
    }()
    
    /// REQ-10
    /// Returns a read/write property that resolves to the name for the given tag.
    func tagName(for row: Row) -> AsyncReadWriteProperty<String> {
        let tagID = TagID(row)
        let name: String? = row[Tag.name].get()
        return self.model.tagName(for: tagID, initialValue: name)
    }
    
    /// REQ-10
    /// Holds the ID of the tag that is selected in the tags list view.
    lazy var selectedTagID: ReadWriteProperty<Set<RelationValue>> = {
        return mutableValueProperty(Set())
    }()
    
    // MARK: - Notes, Created on label, Delete button
    
    /// REQ-11
    /// The item's notes.
    lazy var itemNotes: AsyncReadWriteProperty<String> = {
        return self.model.selectedItemNotes
    }()

    /// REQ-12
    /// The text that appears in the "Created on <date>" label.  This
    /// demonstrates the use of `map` to convert the raw timestamp string
    /// (as stored in the relation) to a display-friendly string.
    lazy var createdOn: AsyncReadableProperty<String> = {
        return self.model.selectedItems
            .project(Item.created)
            .oneString()
            .map{ "Created on \(displayString(from: $0))" }
            .property()
    }()
    
    /// REQ-13
    /// Deletes the selected item.  This demonstrates the use of
    /// `ActionProperty` to expose an imperative (side effect producing)
    /// action as a property that can easily be bound to a `Button`.
    lazy var deleteItem: ActionProperty<()> = ActionProperty { _ in
        self.model.deleteSelectedItem()
    }
}
