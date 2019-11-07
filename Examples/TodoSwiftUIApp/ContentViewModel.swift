//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Combine
import SwiftUI
import PLRelational
import PLRelationalCombine

final class ContentViewModel: ObservableObject {
    
    private let model: Model
    
    let checklistViewModel: ChecklistViewModel
    let detailViewModel: DetailViewModel

    @Published var hasSelection: Bool = false

    private var cancellableBag = Set<AnyCancellable>()

    init(model: Model) {
        self.model = model
        self.checklistViewModel = ChecklistViewModel(model: model)
        self.detailViewModel = DetailViewModel(model: model)
        
        // Set a flag when an item is selected in the list of to-do items.
        model.selectedItems
            .nonEmpty()
            .replaceError(with: false)
            .assign(to: \.hasSelection, on: self)
            .store(in: &cancellableBag)
    }
    
    deinit {
        cancellableBag.forEach{ $0.cancel() }
    }
}
