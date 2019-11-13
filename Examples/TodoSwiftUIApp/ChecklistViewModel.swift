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

        func itemOrder(_ a: Row, _ b: Row) -> Bool {
            // We sort items into two sections:
            //   - first section has all incomplete items, with most recently created items at the top
            //   - second section has all completed items, with most recently completed items at the top
            let aCompleted: String? = a[Item.completed].get()
            let bCompleted: String? = b[Item.completed].get()
            if let aCompleted = aCompleted, let bCompleted = bCompleted {
                // Both items were completed; make more recently completed item come first
                return aCompleted > bCompleted
            } else if aCompleted != nil {
                // `a` was completed but `b` was not, so `a` will come after `b`
                return false
            } else if bCompleted != nil {
                // `b` was completed but `a` was not, so `b` will come after `a`
                return true
            } else {
                // Neither item was completed; make more recently created item come first
                let aCreated: String = a[Item.created].get()!
                let bCreated: String = b[Item.created].get()!
                return aCreated > bCreated
            }
        }
        
        // REQ-2
        // The model for the list of to-do items.
        model.items
            .sortedRows(idAttr: Item.id, orderedBy: itemOrder)
            .replaceError(with: [])
            .map{ rowArray in
                rowArray.map{
                    print("ROW UPDATED: \($0.row)")
                    // TODO: Fix tags
                    let completed = $0.row[Item.completed] != .null
                    return ChecklistItemViewModel(model: model, id: ItemID($0.id), completed: completed, title: $0.row[Item.title].get()!, tags: "...")
                }
            }
            .bind(to: \.itemViewModels, on: self)
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
