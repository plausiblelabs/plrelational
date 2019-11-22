//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Combine
import SwiftUI
import PLRelational
import PLRelationalCombine

final class TagsViewModel: ObservableObject {
    
    private let model: Model
    
    /// The selected item ID, cached in this property for easy access.
    private var itemID: ItemID?

    @Published var newTagName: String = ""
    @Published var tagItemViewModels: [TagItemViewModel] = []
    
    /// Set when the view has displayed one or more items for the first time.
    /// This is used to disable animation the first time items are displayed.
    var hasDisplayedItems = false

    private var cancellableBag = CancellableBag()
    
    init(model: Model) {
        self.model = model

        // Keep the selected item ID cached for easy access
        model.selectedItemIDs
            .oneStringOrNil()
            .replaceError(with: nil)
            .map{ $0.map(ItemID.init) }
            .bind(to: \.itemID, on: self)
            .store(in: &cancellableBag)

        // REQ-2
        // The model for the list of tags.
        model.allTagsWithSelectedItemID
            .changes(TagItem.init)
            .logError()
            .reduce(to: \.tagItemViewModels, on: self, orderBy: { $0.name < $1.name }) { existingTagItemViewModel, tagItem in
                // We reuse existing view model instances if provided; returning nil
                // here means "keep using the existing view model without reinserting"
                if let existing = existingTagItemViewModel {
                    existing.tagItem = tagItem
                    return nil
                } else {
                    return TagItemViewModel(tagItem: tagItem)
                }
            }
            .store(in: &cancellableBag)
    }
    
    deinit {
        cancellableBag.cancel()
    }
    
    /// REQ-9
    /// Creates a new tag of the given name and adds it to the selected to-do item.
    func addNewTagToSelectedItem() {
        if newTagName.isEmpty {
            return
        }

        // Clear the text field
        let name = newTagName
        newTagName = ""

        guard let itemID = self.itemID else {
            return
        }
        
        // See if a tag already exists with the given name
        let existingTag = self.model.allTags.first(where: { $0.name == name })

        if let tag = existingTag {
            // A tag already exists with the given name, so apply that tag
            // rather than creating a new one
            self.model.addExistingTag(tag.id, to: itemID)
        } else {
            // No tag exists with that name, so create a new tag and apply
            // it to this item
            self.model.addNewTag(named: name, to: itemID)
        }
    }
    
    /// REQ-9
    /// Toggles whether a tag is applied to the selected item.
    func toggleApplied(_ tagItem: TagItem) {
        guard let itemID = self.itemID else {
            return
        }

        if tagItem.itemID != nil {
            self.model.removeExistingTag(tagItem.id, from: itemID)
        } else {
            self.model.addExistingTag(tagItem.id, to: itemID)
        }
    }
}
