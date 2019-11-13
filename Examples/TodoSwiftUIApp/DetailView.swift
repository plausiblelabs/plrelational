//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import SwiftUI
import PLRelationalCombine

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
                        // TODO: Context menu not working well in 10.15.1, only seems
                        // selectable if you click the thin border around the cell
                        .contextMenu {
                            Button(action: { /*model.removeTag()*/ } ) {
                                Text("Remove Tag")
                            }
                        }
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
                    Image("trash")
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
