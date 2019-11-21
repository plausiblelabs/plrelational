//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import SwiftUI

struct TagsView: View {
    
    @ObservedObject private var model: TagsViewModel

    init(model: TagsViewModel) {
        self.model = model
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Add a tag", text: $model.newTagName, onCommit: {
                self.model.addNewTagToSelectedItem()
            })
            .autocapitalization(.none)
            .padding()
            
            Divider()
            
            List {
                ForEach(self.model.tagItemViewModels) { tagItemViewModel in
                    TagItemView(model: tagItemViewModel, action: {
                        self.model.toggleApplied(tagItemViewModel.tagItem)
                    })
                    .frame(minWidth: 0, maxWidth: .infinity)
                }
            }
            .environment(\.defaultMinListRowHeight, TagItemView.rowHeight)
        }
    }
}

struct TagsView_Previews: PreviewProvider {
    static var previews: some View {
        let model = modelForPreview()
        return TagsView(model: TagsViewModel(model: model))
            .padding()
    }
}
