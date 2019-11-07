//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Combine
import SwiftUI
import PLRelational
import PLRelationalCombine

final class DetailViewModel: ObservableObject {
    
    private let model: Model

    /// The selected item ID, cached in this property for easy access.
    private var itemID: ItemID?
    
    @Published var itemTitle: String = ""
    @Published var itemTitleAgain: String = ""

    @Published var availableTags: [ComboBoxItem] = []
    @Published var itemTags: [String] = []

    @Published var createdOn: String = ""

    private var cancellableBag = Set<AnyCancellable>()

    init(model: Model) {
        self.model = model

        // Keep the selected item ID cached for easy access
        model.selectedItemIDs
            .oneStringOrNil()
            .replaceError(with: nil)
            .map{ $0.map(ItemID.init) }
            .assign(to: \.itemID, on: self)
            .store(in: &cancellableBag)

        // Bind selected item title to `itemTitle`
        model.selectedItems
            .project(Item.title)
            .oneString()
            .replaceError(with: "")
            .assign(to: \.itemTitle, on: self)
            .store(in: &cancellableBag)

        /// REQ-9
        /// The tags that are available (i.e., not already applied) for the selected
        /// to-do item, sorted by name.
        model.availableTagsForSelectedItem
            .sortedRows(idAttr: Tag.id, orderAttr: Tag.name)
            .replaceError(with: [])
            .map{ rowArray in
                rowArray.map{
                    ComboBoxItem(id: $0.id, string: $0.row[Tag.name].get()!)
                }
            }
            .assign(to: \.availableTags, on: self)
            .store(in: &cancellableBag)

        // REQ-10
        // The tags associated with the selected to-do item, sorted by name.
        model.tagsForSelectedItem
            .sortedRows(idAttr: Tag.id, orderAttr: Tag.name)
            .replaceError(with: [])
            .map{ $0.compactMap{ $0.row[Tag.name].get() } }
            .assign(to: \.itemTags, on: self)
            .store(in: &cancellableBag)

        // REQ-12
        // The text that appears in the "Created on <date>" label.  This
        // demonstrates the use of `map` to convert the raw timestamp string
        // (as stored in the relation) to a display-friendly string.
        model.selectedItems
            .project(Item.created)
            .oneString()
            .replaceError(with: "unknown date")
            .map{ "Created on \(displayString(from: $0))" }
            .assign(to: \.createdOn, on: self)
            .store(in: &cancellableBag)
    }
    
    deinit {
        cancellableBag.forEach{ $0.cancel() }
    }
    
    /// REQ-9
    /// Adds an existing tag to the selected to-do item.
    func addExistingTagToSelectedItem(tagID: RelationValue) {
        guard let itemID = self.itemID else {
            return
        }

        self.model.addExistingTag(TagID(tagID), to: itemID)
    }
    
    /// REQ-9
    /// Creates a new tag of the given name and adds it to the selected to-do item.
    func addNewTagToSelectedItem(name: String) {
        guard let itemID = self.itemID else {
            return
        }
        
        // See if a tag already exists with the given name
        let existingTag = self.model.allTags.first(where: {
            let rowName: String = $0.row[Tag.name].get()!
            return name == rowName
        })
        
        if let elem = existingTag {
            // A tag already exists with the given name, so apply that tag
            // rather than creating a new one
            let tagID = TagID(elem.id)
            self.model.addExistingTag(tagID, to: itemID)
        } else {
            // No tag exists with that name, so create a new tag and apply
            // it to this item
            self.model.addNewTag(named: name, to: itemID)
        }
    }
    
    /// REQ-13
    /// Deletes the selected item.
    func deleteSelectedItem() {
        self.model.deleteSelectedItem()
    }
}
