//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import SwiftUI

struct CheckButton: View {
    
    let isOn: Binding<Bool>
    
    var body: some View {
        let checkName = isOn.wrappedValue ?
            "checkmark.circle" : "circle"
        return Image(systemName: checkName)
            .imageScale(.large)
            .frame(minWidth: 28, maxHeight: .infinity)
            .onTapGesture { self.isOn.wrappedValue.toggle() }
    }
}

