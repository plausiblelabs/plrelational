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
    
    let detailViewModel: DetailViewModel
    
    @Published var newItemTitle: String = ""
    @Published var itemViewModels: [ChecklistItemViewModel] = []
    @Published var selectedItem: ItemID? {
        didSet {
            // XXX: When the back button is tapped on the detail screen,
            // NavigationLink will clear the selected item right away,
            // before we have a chance to commit text changes (apparently
            // the selection change happens before the end editing event
            // is sent.  As a workaround, we won't actually clear the
            // selection at the relation level.  This needs more thought.
            // Maybe it's just not a good idea to rely on the end editing
            // event to fire in order to commit text (vs having an explicit
            // save button or something).
            if let itemID = selectedItem {
                self.model.selectedItemIDs
                    .asyncReplaceValues([itemID.relationValue])
            }
        }
    }
    
    /// Set when the view has displayed one or more items for the first time.
    /// This is used to disable animation the first time items are displayed.
    var hasDisplayedItems = false

    private var cancellableBag = CancellableBag()
    
    init(model: Model) {
        self.model = model
        self.detailViewModel = DetailViewModel(model: model)

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
    
    /// Delete the items in the given index set.
    func deleteItems(_ items: IndexSet) {
        // TODO: For now we assume there's only one item
        if let index = items.first {
            let itemViewModel = itemViewModels[index]
            model.deleteItem(itemViewModel.item.id)
        }
    }
}
