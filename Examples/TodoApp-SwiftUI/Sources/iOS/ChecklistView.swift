//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import SwiftUI

struct DummyView: View {
    var body: some View {
        Text("Hi")
    }
}

struct ChecklistView: View {
    
    @ObservedObject private var model: ChecklistViewModel

    init(model: ChecklistViewModel) {
        self.model = model
    }
    
    var body: some View {
        // Disable animation for initial load
        // TODO: This seems to have no effect on iOS
        let animation: Animation?
        if model.hasDisplayedItems {
            animation = .default
        } else {
            if model.itemViewModels.count > 0 {
                model.hasDisplayedItems = true
            }
            animation = nil
        }
        
        return VStack(spacing: 0) {
            TextField("Add a task", text: $model.newItemTitle, onCommit: {
                self.model.addNewItem()
            })
            .padding()
            
            Divider()
            
            List(selection: $model.selectedItem) {
                ForEach(self.model.itemViewModels) { itemViewModel in
                    NavigationLink(destination: DetailView(model: self.model.detailViewModel),
                                   tag: itemViewModel.item.id,
                                   selection: self.$model.selectedItem)
                    {
                        ChecklistItemView(model: itemViewModel)
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .animation(.none)
                    }
                }
                .onDelete(perform: self.model.deleteItems)
            }
            .animation(animation)
            .environment(\.defaultMinListRowHeight, ChecklistItemView.rowHeight)
        }
    }
}

struct ChecklistView_Previews: PreviewProvider {
    static var previews: some View {
        let model = modelForPreview()
        let viewModel = ChecklistViewModel(model: model)
        return ChecklistView(model: viewModel)
            .padding()
            .previewLayout(.fixed(width: 300, height: 400))
    }
}
