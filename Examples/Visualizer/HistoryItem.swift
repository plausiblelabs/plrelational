//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import PLRelational

struct HistoryItem {
    let id: HistoryItemID
    let tabID: TabID
    let outlinePath: DocOutlinePath
    let position: Int64
}

extension HistoryItem: Equatable {}
func ==(a: HistoryItem, b: HistoryItem) -> Bool {
    return a.id == b.id
}

extension HistoryItem: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
