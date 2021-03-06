//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import SwiftUI

struct ContentView: View {
    
    @ObservedObject private var model: ContentViewModel
    
    init(model: ContentViewModel) {
        self.model = model
    }

    var body: some View {
        NavigationView {
            ChecklistView(model: model.checklistViewModel)
                .navigationBarTitle("To Do", displayMode: .inline)
            // TODO: On iPad, the following would be the preferred way
            // of having a split master/detail view, but for now we'll
            // focus on iPhone
//            DetailView(model: model.checklistViewModel.detailViewModel)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let model = modelForPreview()
        let viewModel = ContentViewModel(model: model)
        return Group {
            ContentView(model: viewModel)
                .previewDevice(PreviewDevice(rawValue: "iPhone 8"))
                .previewDisplayName("iPhone 8")
            
//            ContentView(model: viewModel)
//                .previewDevice(PreviewDevice(rawValue: "iPad Pro (9.7-inch)"))
//                .previewDisplayName("iPad Pro")
        }
    }
}
