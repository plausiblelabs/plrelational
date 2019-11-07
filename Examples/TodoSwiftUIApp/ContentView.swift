//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import SwiftUI
import PLRelationalCombine

struct ContentView: View {
    
    @ObservedObject private var model: ContentViewModel

    init(model: ContentViewModel) {
        self.model = model
    }

    var body: some View {
        HStack(spacing: 20) {
            ChecklistView(model: model.checklistViewModel)
                .frame(minWidth: 290, minHeight: 400)
            
            ZStack {
                if model.hasSelection {
                    DetailView(model: model.detailViewModel)
                        .padding()
                        .background(Color(white: 0.25))
                        .cornerRadius(8)
                } else {
                    Text("No Selection")
                        .font(.system(size: 19))
                        .foregroundColor(Color.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
                .frame(minWidth: 290, minHeight: 400)
        }
            .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let model = modelForPreview()
        let viewModel = ContentViewModel(model: model)
        return ContentView(model: viewModel)
            .previewLayout(.fixed(width: 600, height: 440))
    }
}
