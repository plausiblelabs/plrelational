//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Combine
import SwiftUI
import PLRelationalCombine

final class ChecklistItemViewModel: Identifiable, ObservableObject {
    
    private let model: Model

    let id: ItemID
    @Published var title: String
    @Published var tags: String
    @Published var checked: Bool = false
    
    private var cancellableBag = Set<AnyCancellable>()

    init(model: Model, id: ItemID, title: String, tags: String) {
        self.model = model
        self.id = id
        self.title = title
        self.tags = tags
        
        // REQ-5
        // Each to-do item should have a string containing the
        // list of tags for that item.
        self.model
            .tagsString(for: id)
            .weakAssign(to: \.tags, on: self)
            .store(in: &cancellableBag)
    }
    
    deinit {
//        print("CANCELLING: \(id)")
        cancellableBag.forEach{ $0.cancel() }
    }
}
