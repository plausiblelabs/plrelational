//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Combine
import SwiftUI
import PLRelational
import PLRelationalCombine

final class ChecklistViewModel: ObservableObject {
    
    private let model: Model
    
    @Published var newItemTitle: String = ""
    @Published var itemViewModels: [ChecklistItemViewModel] = []
    @Published var selectedItem: ItemID? {
        didSet {
            let itemIDs: [RelationValue]
            if let itemID = selectedItem {
                itemIDs = [itemID.relationValue]
            } else {
                itemIDs = []
            }
            self.model.selectedItemIDs
                .asyncReplaceValues(itemIDs)
        }
    }
    
    /// Set when the view has displayed one or more items for the first time.
    /// This is used to disable animation the first time items are displayed.
    var hasDisplayedItems = false

    private var cancellableBag = CancellableBag()
    
    init(model: Model) {
        self.model = model

        // REQ-2
        // The model for the list of to-do items.
        model.items
            .changes(ChecklistItem.init)
            .logError()
            .reduce(to: \.itemViewModels, on: self, orderBy: itemOrder) { existingItemViewModel, item in
                // We reuse existing view model instances if provided; returning nil
                // here means "keep using the existing view model without reinserting"
                if let existing = existingItemViewModel {
                    existing.item = item
                    return nil
                } else {
                    return ChecklistItemViewModel(model: self.model, item: item)
                }
            }
            .store(in: &cancellableBag)
    }
    
    deinit {
        cancellableBag.cancel()
    }
    
    /// REQ-1
    /// Creates a new to-do item using the title from the text field.
    func addNewItem() {
        if newItemTitle.isEmpty {
            return
        }

        // Add the new item
        _ = model.addNewItem(with: newItemTitle)
        
        // Clear the text field
        newItemTitle = ""
    }
}
