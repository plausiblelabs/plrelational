//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

// Based on:
//   https://gist.github.com/unnamedd/6e8c3fbc806b8deb60fa65d6b9affab0

import AppKit
import Combine
import SwiftUI
import PLRelational

/// A wrapper around NSTextView to allow it to be used in SwiftUI.
struct TextView: NSViewRepresentable {
    
    @Binding var text: String
    
    var onEditingChanged: () -> Void = {}
    var onCommit: () -> Void = {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> CustomTextView {
        let textView = CustomTextView(text: self.text)
        textView.delegate = context.coordinator
        return textView
    }
    
    func updateNSView(_ view: CustomTextView, context: Context) {
        view.text = text
        view.selectedRanges = context.coordinator.selectedRanges
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

extension TextView {
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TextView
        var selectedRanges: [NSValue] = []
        
        init(_ parent: TextView) {
            self.parent = parent
        }
        
        func textDidBeginEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            
            self.parent.text = textView.string
            self.parent.onEditingChanged()
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            
            self.parent.text = textView.string
            self.selectedRanges = textView.selectedRanges
        }
        
        func textDidEndEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            
            self.parent.text = textView.string
            self.parent.onCommit()
        }
    }
}

final class CustomTextView: NSView {
    private var isEditable: Bool
    private var font: NSFont
    
    weak var delegate: NSTextViewDelegate?
    
    var text: String {
        didSet {
            textView.string = text
        }
    }
    
    var selectedRanges: [NSValue] = [] {
        didSet {
            guard selectedRanges.count > 0 else {
                return
            }
            
            textView.selectedRanges = selectedRanges
        }
    }
    
    private lazy var scrollView: NSScrollView = {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = true
        scrollView.borderType = .lineBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalRuler = false
        scrollView.autoresizingMask = [.width, .height]
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        
        return scrollView
    }()
    
    private lazy var textView: NSTextView = {
        let contentSize = scrollView.contentSize
        let textStorage = NSTextStorage()
        
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        
        let textContainer = NSTextContainer(containerSize: scrollView.frame.size)
        textContainer.widthTracksTextView = true
        textContainer.containerSize = NSSize(
            width: contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        
        layoutManager.addTextContainer(textContainer)
        
        let textView                     = NSTextView(frame: .zero, textContainer: textContainer)
        textView.autoresizingMask        = .width
        textView.backgroundColor         = NSColor.textBackgroundColor
        textView.delegate                = self.delegate
        textView.drawsBackground         = true
        textView.font                    = self.font
        textView.isEditable              = self.isEditable
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable   = true
        textView.maxSize                 = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize                 = NSSize(width: 0, height: contentSize.height)
        textView.textColor               = NSColor.labelColor
        textView.textContainerInset      = NSSize(width: 0, height: 4)
    
        return textView
    }()
    
    // MARK: - Init
    
    init(text: String, isEditable: Bool = true, font: NSFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)) {
        self.font       = font
        self.isEditable = isEditable
        self.text       = text

        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Life cycle
    
    override func viewWillDraw() {
        super.viewWillDraw()
        
        setupScrollViewConstraints()
        setupTextView()
    }
    
    func setupScrollViewConstraints() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(scrollView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor)
        ])
    }
    
    func setupTextView() {
        scrollView.documentView = textView
    }
}
