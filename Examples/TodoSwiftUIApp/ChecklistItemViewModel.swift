//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Combine
import SwiftUI
import PLRelational
import PLRelationalCombine

final class ChecklistItemViewModel: Identifiable, ObservableObject {
    
    private let model: Model

    let id: ItemID
    @TwoWay var completed: Bool
    @Published var title: String
    @Published var tags: String
    
    private var cancellableBag = Set<AnyCancellable>()

    init(model: Model, id: ItemID, completed: Bool, title: String, tags: String) {
        self.model = model
        self.id = id
        self.completed = completed
        self.title = title
        self.tags = tags
        
        // REQ-3
        // Each to-do item should have a checkbox showing its completion status.
        // This is a two-way property that is backed by UndoableDatabase.
        model.items
            .select(Item.id *== id)
            .project(Item.completed)
            .bind(to: \._completed, on: self, strategy: model.itemCompleted())
            .store(in: &cancellableBag)
        
        // TODO: REQ-4 / title
        
        // REQ-5
        // Each to-do item should have a string containing the
        // list of tags for that item.
        self.model
            .tagsString(for: id)
            .bind(to: \.tags, on: self)
            .store(in: &cancellableBag)
    }
    
    deinit {
//        print("CANCELLING: \(id)")
        cancellableBag.forEach{ $0.cancel() }
    }
}
