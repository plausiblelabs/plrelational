//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelational
import PLRelationalBinding
import PLBindableControls

class ChecklistViewModel {
    
    // text field
    // list view
    //   checkbox
    //   text
    //   tags
    
    private let model: Model
    
    init(model: Model) {
        self.model = model
    }
    
    lazy var itemsListModel: ListViewModel<RowArrayElement> = {
        return ListViewModel(
            data: self.model.items.arrayProperty(idAttr: Item.id, orderAttr: Item.status),
            contextMenu: nil,
            move: nil,
            cellIdentifier: { _ in "Cell" },
            cellText: { row in
                let rowID = row[Item.id]
                let initialValue: String? = row[Item.title].get()
                let textRelation = self.model.items.select(Item.id *== rowID).project(Item.title)
                return .asyncReadWrite(self.model.itemTitle(textRelation, initialValue: initialValue))
            },
            cellImage: nil
        )
    }()
    
    lazy var itemsListSelection: AsyncReadWriteProperty<Set<RelationValue>> = {
        return self.model.undoableBidiProperty(
            action: "Change Selection",
            signal: self.model.selectedItemIDs.allRelationValues(),
            update: { self.model.selectedItemIDs.asyncReplaceValues(Array($0)) }
        )
    }()
}
