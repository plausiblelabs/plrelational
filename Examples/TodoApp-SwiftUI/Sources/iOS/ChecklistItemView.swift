//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import SwiftUI

struct ChecklistItemView: View {

    static let rowHeight: CGFloat = 34
    
    @ObservedObject private var model: ChecklistItemViewModel

    init(model: ChecklistItemViewModel) {
        self.model = model
    }
    
    var body: some View {
        HStack(alignment: .center) {
            CheckButton(isOn: $model.completed)
            VStack(alignment: .leading) {
                Text(model.title)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !model.tags.isEmpty {
                    Text(model.tags)
                        .lineLimit(1)
                        .font(.system(size: 11))
                        .foregroundColor(Color.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minHeight: ChecklistItemView.rowHeight)
    }
}

struct ChecklistItemView_Previews: PreviewProvider {
    static var previews: some View {
        let (model, itemIds) = modelForPreviewWithIds()
        let viewModel = ChecklistItemViewModel(model: model, item: ChecklistItem(id: itemIds[0], title: "Item 1", created: "", completed: ""))
        return ChecklistItemView(model: viewModel)
            .padding()
            .previewLayout(.fixed(width: 300, height: ChecklistItemView.rowHeight))
    }
}
