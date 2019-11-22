//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Combine
import SwiftUI
import PLRelational
import PLRelationalCombine

final class DetailViewModel: ObservableObject {
    
    private let model: Model

    let tagsViewModel: TagsViewModel

    @TwoWay(onSet: .commit) var itemCompleted: Bool = false
    @TwoWay var itemTitle: String = ""
    @Published var itemTags: String = ""
    @TwoWay var itemNotes: String = ""
    
    @Published var createdOn: String = ""

    private var cancellableBag = CancellableBag()

    init(model: Model) {
        self.model = model
        // TODO: Initialize this lazily?
        self.tagsViewModel = TagsViewModel(model: model)

        // REQ-7
        // The item's completion status.  This is a two-way property that
        // is backed by UndoableDatabase.
        model.selectedItems
            .project(Item.completed)
            .bind(to: \._itemCompleted, on: self, strategy: model.itemCompleted())
            .store(in: &cancellableBag)

        // REQ-8
        // The item's title.  This is a two-way property that is backed
        // by UndoableDatabase, so any changes made to it in the text field
        // can be rolled back by the user.
        model.selectedItems
            .project(Item.title)
            .bind(to: \._itemTitle, on: self, strategy: model.itemTitle())
            .store(in: &cancellableBag)

        // REQ-10
        // The tags associated with the selected to-do item, sorted by name.
        model.tagsForSelectedItem
            .sortedStrings(for: Tag.name)
            .replaceError(with: [])
            .map{ $0.joined(separator: ", ") }
            .bind(to: \.itemTags, on: self)
            .store(in: &cancellableBag)

        // REQ-11
        // The item's notes.  This is a two-way property that is backed
        // by UndoableDatabase, so any changes made to it in the text view
        // can be rolled back by the user.
        model.selectedItems
            .project(Item.notes)
            .bind(to: \._itemNotes, on: self, strategy: model.itemNotes())
            .store(in: &cancellableBag)
        
        // REQ-12
        // The text that appears in the "Created on <date>" label.  This
        // demonstrates the use of `map` to convert the raw timestamp string
        // (as stored in the relation) to a display-friendly string.
        model.selectedItems
            .project(Item.created)
            .oneString()
            .replaceError(with: "unknown date")
            .map{ "Created on \(displayString(from: $0))".uppercased() }
            .bind(to: \.createdOn, on: self)
            .store(in: &cancellableBag)
    }
    
    deinit {
        cancellableBag.cancel()
    }
    
    /// REQ-8
    /// Commits the current value of `itemTitle` to the underlying relation.  This should be
    /// called from the associated TextField's `onCommit` function.
    func commitItemTitle() {
        _itemTitle.commit()
    }

    /// REQ-11
    /// Commits the current value of `itemNotes` to the underlying relation.  This should be
    /// called from the associated TextView's `onCommit` function.
    func commitItemNotes() {
        _itemNotes.commit()
    }
}
