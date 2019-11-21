//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Combine
import SwiftUI
import PLRelational
import PLRelationalCombine

struct TagItem: Identifiable {
    let id: TagID
    let name: String
    let itemID: ItemID?
    
    init(id: TagID, name: String, itemID: ItemID?) {
        self.id = id
        self.name = name
        self.itemID = itemID
    }

    init(row: Row) {
        self.id = TagID(row[Tag.id])
        self.name = row[Tag.name].get()!
        if let itemID = row[Item.id].get() as String? {
            self.itemID = ItemID(itemID)
        } else {
            self.itemID = nil
        }
    }
}

final class TagItemViewModel: ElementViewModel, Identifiable, ObservableObject {

    var tagItem: TagItem
    var element: TagItem { tagItem }
    var id: TagID { tagItem.id }

    init(tagItem: TagItem) {
        self.tagItem = tagItem
    }
}
