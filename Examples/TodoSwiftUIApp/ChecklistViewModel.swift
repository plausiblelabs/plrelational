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

    private var cancellableBag = Set<AnyCancellable>()
    
    init(model: Model) {
        self.model = model

        func itemOrder(_ a: ChecklistItem, _ b: ChecklistItem) -> Bool {
            // We sort items into two sections:
            //   - first section has all incomplete items, with most recently created items at the top
            //   - second section has all completed items, with most recently completed items at the top
            if let aCompleted = a.completed, let bCompleted = b.completed {
                // Both items were completed; make more recently completed item come first
                return aCompleted >= bCompleted
            } else if a.completed != nil {
                // `a` was completed but `b` was not, so `a` will come after `b`
                return false
            } else if b.completed != nil {
                // `b` was completed but `a` was not, so `b` will come after `a`
                return true
            } else {
                // Neither item was completed; make more recently created item come first
                return a.created >= b.created
            }
        }
        
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
        cancellableBag.forEach{ $0.cancel() }
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
