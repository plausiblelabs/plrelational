//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Combine
import SwiftUI
import PLRelational
import PLRelationalCombine

struct DummyItem: Identifiable {
    var id: Int
    var title: String
    var tags: String
}

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

    private var cancellableBag = Set<AnyCancellable>()
    
    init(model: Model) {
        self.model = model
        
        // REQ-2
        // The model for the list of to-do items.
        model.items
            .sortedRows(idAttr: Item.id, orderAttr: Item.status, descending: true)
            .replaceError(with: [])
            .map{ rowArray in
                rowArray.map{
                    print("ROW UPDATED: \($0.row)")
                    // TODO: Fix tags and checked
                    return ChecklistItemViewModel(model: model, id: ItemID($0.id), title: $0.row[Item.title].get()!, tags: "...")
                }
            }
            .assign(to: \.itemViewModels, on: self)
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
