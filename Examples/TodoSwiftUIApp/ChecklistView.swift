//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import SwiftUI
import PLRelationalCombine

struct ChecklistView: View {
    
    @ObservedObject private var model: ChecklistViewModel

    init(model: ChecklistViewModel) {
        self.model = model
    }
    
    var body: some View {
        VStack {
            TextField("Add a to-do", text: $model.newItemTitle, onCommit: {
                self.model.addNewItem()
            })
                .padding(.bottom, 10)
            
            List(selection: $model.selectedItem) {
                ForEach(self.model.itemViewModels) { itemViewModel in
                    ChecklistItemView(model: itemViewModel)
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .animation(.none)
                }
            }
                // TODO: Disable animation for initial load
                .animation(.default)
                .environment(\.defaultMinListRowHeight, 30)
        }
    }
}

struct ChecklistView_Previews: PreviewProvider {
    static var previews: some View {
        let model = modelForPreview()
        let viewModel = ChecklistViewModel(model: model)
        return ChecklistView(model: viewModel)
            .padding()
            .previewLayout(.fixed(width: 300, height: 100))
    }
}
