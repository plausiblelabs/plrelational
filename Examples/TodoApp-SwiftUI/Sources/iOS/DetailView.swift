//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import SwiftUI

struct DetailView: View {
    
    @ObservedObject private var model: DetailViewModel
    @State var showingSheet: Bool = false

    init(model: DetailViewModel) {
        self.model = model
    }
    
    var body: some View {
        func label(_ text: String) -> some View {
            return Text(text)
                .font(.system(size: 12))
                .fontWeight(.bold)
                .foregroundColor(.gray)
        }
        
        func divider() -> some View {
            Divider()
                .padding(.bottom, 8)
        }
        
        return VStack(alignment: .leading) {
            HStack(alignment: .center) {
                CheckButton(isOn: $model.itemCompleted)
                TextField("", text: $model.itemTitle, onEditingChanged: { editing in
                    if !editing {
                        self.model.commitItemTitle()
                    }
                })
            }
            .frame(maxHeight: 40)

            divider()
            HStack(alignment: .center) {
                label("TAGS")
                Spacer()
                Button(action: { self.showingSheet = true }) {
                    Image(systemName: "pencil.circle")
                        .accentColor(.gray)
                        .imageScale(.large)
                }
            }

            if model.itemTags.isEmpty {
                Button("Add a tag", action: { self.showingSheet = true })
                    .frame(minHeight: 50, alignment: .center)
            } else {
                Text(model.itemTags)
                    .lineLimit(5)
                    .frame(minHeight: 50, alignment: .topLeading)
            }
            
            divider()
            label("NOTES")
            TextView(text: $model.itemNotes, onCommit: { self.model.commitItemNotes() })
                .padding(.bottom)

            divider()
            label(model.createdOn)
        }
        .padding()
        .sheet(isPresented: $showingSheet) {
            NavigationView {
                TagsView(model: self.model.tagsViewModel)
                    .navigationBarTitle("Edit Tags", displayMode: .inline)
                    .navigationBarItems(trailing: Button(action: { self.showingSheet = false }) {
                        // TODO: Is there a better way to get a bold/default bar item in SwiftUI?
                        Text("Done")
                            .fontWeight(.bold)
                    })
            }
        }
    }
}

struct DetailView_Previews: PreviewProvider {
    static var previews: some View {
        let model = modelForPreview()
        let viewModel = DetailViewModel(model: model)
        return DetailView(model: viewModel)
            .previewDevice(PreviewDevice(rawValue: "iPhone 8"))
            .previewDisplayName("iPhone 8")
    }
}
