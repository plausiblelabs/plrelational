//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import SwiftUI

struct TagItemView: View {

    static let rowHeight: CGFloat = 34
    
    @ObservedObject private var model: TagItemViewModel
    private let action: () -> Void

    init(model: TagItemViewModel, action: @escaping () -> Void) {
        self.model = model
        self.action = action
    }
    
    var body: some View {
        HStack(alignment: .center) {
            ZStack {
                if model.tagItem.itemID != nil {
                    Image(systemName: "checkmark")
                } else {
                    EmptyView()
                }
            }
            .frame(width: 20, height: 20)

            Button(action: self.action) {
                Text(model.tagItem.name)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minHeight: ChecklistItemView.rowHeight, alignment: .leading)
    }
}

struct TagItemView_Previews: PreviewProvider {
    static var previews: some View {
        return List {
            TagItemView(model: TagItemViewModel(tagItem: TagItem(id: TagID("1"), name: String(repeating: "Tag 1 ", count: 20), itemID: ItemID("1"))), action: {})
            TagItemView(model: TagItemViewModel(tagItem: TagItem(id: TagID("2"), name: "Tag 2", itemID: nil)), action: {})
        }
        .environment(\.defaultMinListRowHeight, TagItemView.rowHeight)
        .padding()
    }
}
