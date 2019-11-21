//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Combine
import SwiftUI
import PLRelational
import PLRelationalCombine

final class ChecklistItemViewModel: ElementViewModel, Identifiable, ObservableObject {
    
    private let model: Model

    var item: ChecklistItem {
        didSet {
            // REQ-4
            // Keep the list item title up to date.  Note that we could have set up
            // a binding in `init` below similar to what we do for the tags label,
            // but using `didSet` here demonstrates another approach.  Since the
            // `reduce(to:)` will see an update every time the title gets changed
            // by the detail view, and since it already sets the updated view model's
            // `item`, we can just update `title` here.
            self.title = item.title
        }
    }
    var element: ChecklistItem { item }
    var id: ItemID { item.id }

    @TwoWay(onSet: .commit) var completed: Bool = false
    @Published var title: String
    @Published var tags: String
    
    private var cancellableBag = CancellableBag()
    
    init(model: Model, item: ChecklistItem) {
        self.model = model
        self.item = item
        self.title = item.title
        self.tags = ""

        // REQ-3
        // Each to-do item should have a checkbox showing its completion status.
        // This is a two-way property that is backed by UndoableDatabase.
        model.items
            .select(Item.id *== id)
            .project(Item.completed)
            .bind(to: \._completed, on: self, strategy: model.itemCompleted())
            .store(in: &cancellableBag)

        // REQ-5
        // Each to-do item should have a string containing the
        // list of tags for that item.
        self.model
            .tagsString(for: id)
            .bind(to: \.tags, on: self)
            .store(in: &cancellableBag)
    }
    
    deinit {
        cancellableBag.cancel()
    }
}
