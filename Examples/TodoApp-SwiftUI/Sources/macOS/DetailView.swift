//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import SwiftUI

struct DetailView: View {
    
    @ObservedObject private var model: DetailViewModel

    init(model: DetailViewModel) {
        self.model = model
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .center) {
                Toggle(isOn: $model.itemCompleted) {
                    Text(" ")
                }
                TextField("", text: $model.itemTitle, onCommit: { self.model.commitItemTitle() })
            }
                .padding(.bottom)
            
            EphemeralComboBox(
                placeholder: "Assign a tag",
                items: $model.availableTags,
                onCommitString: { self.model.addNewTagToSelectedItem(name: $0) },
                onItemSelected: { self.model.addExistingTagToSelectedItem(tagID: $0.id) }
            )

            List {
                ForEach(model.itemTags, id: \.self) { tag in
                    Text(tag)
                }
            }
            .padding(.bottom)
            
            Text("Notes")
            TextView(text: $model.itemNotes, onCommit: { self.model.commitItemNotes() })
                .padding(.bottom)

            HStack {
                Text(model.createdOn)
                Spacer()
                Button(action: model.deleteSelectedItem) {
                    Image("Trash")
                }.buttonStyle(BorderlessButtonStyle())
            }
        }
    }
}

struct DetailView_Previews: PreviewProvider {
    static var previews: some View {
        let model = modelForPreview()
        let viewModel = DetailViewModel(model: model)
        return DetailView(model: viewModel)
            .padding()
            .previewLayout(.fixed(width: 300, height: 400))
    }
}
