//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import SwiftUI
import PLRelationalCombine

struct ChecklistItemView: View {

    @ObservedObject private var model: ChecklistItemViewModel

    init(model: ChecklistItemViewModel) {
        self.model = model
    }
    
    var body: some View {
        HStack(alignment: .center) {
            Toggle(isOn: $model.completed) {
                Text(" ")
            }
            Text(model.title)
            Spacer()
            Text(model.tags)
                .font(.system(size: 11))
                .foregroundColor(Color.secondary)
        }
    }
}

struct ChecklistItemView_Previews: PreviewProvider {
    static var previews: some View {
        let model = modelForPreview()
        let viewModel = ChecklistItemViewModel(model: model, item: ChecklistItem(id: ItemID("1"), title: "Item 1", created: "", completed: ""))
        return ChecklistItemView(model: viewModel)
            .padding()
            .previewLayout(.fixed(width: 300, height: 30))
    }
}
