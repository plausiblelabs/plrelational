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

    private var cancellableBag = CancellableBag()

    init(model: Model) {
        self.model = model
        self.checklistViewModel = ChecklistViewModel(model: model)
    }
    
    deinit {
        cancellableBag.cancel()
    }
}
