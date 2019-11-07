//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import SwiftUI
import PLRelationalCombine

struct DetailView: View {
    
    @ObservedObject private var model: DetailViewModel

    // TODO: Move these to ViewModel
    @State private var notes: String = ""
    //@State private var tagsListSelection = Set<String>()
    @State private var checked = false

    init(model: DetailViewModel) {
        self.model = model
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .lastTextBaseline) {
                Toggle(isOn: $checked) {
                    Text("")
                }
//                Text("READONLY (\(model.itemTitle))")
                TextField("", text: $model.itemTitle)
//                TextField("Two", text: $model.itemTitleAgain)
//                TextField("Two", text: $model.itemTitle)
            }
                .padding(.bottom)
            
            EphemeralComboBox(
                placeholder: "Assign a tag",
                items: $model.availableTags,
                onCommitString: { self.model.addNewTagToSelectedItem(name: $0) },
                onItemSelected: { self.model.addExistingTagToSelectedItem(tagID: $0.id) }
            )
            
            List { //(selection: $tagsListSelection) {
                ForEach(model.itemTags, id: \.self) { tag in
                    Text(tag)
                }
            }
                .padding(.bottom)
            
            Text("Notes")
            // TODO: Multi-line TextField not yet working in SwiftUI
            TextField("", text: $notes)
                .multilineTextAlignment(/*@START_MENU_TOKEN@*/.leading/*@END_MENU_TOKEN@*/)
                .lineLimit(nil) // 5?
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 100, maxHeight: 100, alignment: .topLeading)
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
