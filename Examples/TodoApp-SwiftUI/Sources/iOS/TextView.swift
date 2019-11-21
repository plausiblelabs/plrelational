//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

// Based on:
//   https://stackoverflow.com/a/57853937

import SwiftUI

/// A wrapper around UITextView to allow it to be used in SwiftUI.
struct TextView: UIViewRepresentable {
    
    @Binding var text: String

    var onCommit: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let uiTextView = UITextView()
        uiTextView.delegate = context.coordinator

        uiTextView.font = UIFont.systemFont(ofSize: 16)
        uiTextView.isScrollEnabled = true
        uiTextView.isEditable = true
        uiTextView.isUserInteractionEnabled = true

        // XXX: Remove all padding
        uiTextView.textContainerInset = .zero
        uiTextView.textContainer.lineFragmentPadding = 0
        
        return uiTextView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.text = text
    }

    class Coordinator : NSObject, UITextViewDelegate {
        var parent: TextView

        init(_ uiTextView: TextView) {
            self.parent = uiTextView
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            return true
        }

        func textViewShouldEndEditing(_ textView: UITextView) -> Bool {
            self.parent.text = textView.text
            self.parent.onCommit()
            return true
        }
    }
}

#if DEBUG
struct TextView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            TextView(text: .constant("hello\nthere"))
        }
            .padding()
            .previewLayout(.fixed(width: 300, height: 200))
    }
}
#endif
