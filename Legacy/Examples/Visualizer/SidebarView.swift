//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelational
import PLRelationalBinding
import PLBindableControls

class SidebarView: BackgroundView {
    
    private let model: DocModel
    
    private var segmentedControl: NSSegmentedControl!
    private var contentView: BackgroundView!
    
    init(frame: NSRect, model: DocModel) {
        self.model = model
        
        super.init(frame: frame)
        
        let segmentedControl = NSSegmentedControl()
        segmentedControl.segmentCount = 2
        segmentedControl.setLabel("Code", forSegment: 0)
        segmentedControl.setLabel("Properties", forSegment: 1)
        segmentedControl.selectedSegment = 0
        segmentedControl.sizeToFit()
        var sframe = segmentedControl.frame
        sframe.origin.x = round(bounds.midX - (sframe.width * 0.5))
        sframe.origin.y = 10
        segmentedControl.frame = sframe
        addSubview(segmentedControl)
        
        contentView = BackgroundView(frame: NSMakeRect(0, 43, frame.width, frame.height - 43))
        contentView.autoresizingMask = [.height]
        addSubview(contentView)
        
        let codeSegmentView = CodeSegmentView(frame: contentView.bounds, model: model)
        codeSegmentView.autoresizingMask = [.width, .height]
        let propsSegmentView = PropsSegmentView(frame: contentView.bounds, model: model)
        propsSegmentView.autoresizingMask = [.width, .height]
        contentView.addSubview(codeSegmentView)
        
        segmentedControl.setAction({ [weak self] control in
            guard let strongSelf = self else { return }
            guard let contentView = strongSelf.contentView else { return }
            contentView.subviews.forEach{ $0.removeFromSuperview() }
            if control.selectedSegment == 0 {
                codeSegmentView.frame = contentView.bounds
                contentView.addSubview(codeSegmentView)
            } else {
                propsSegmentView.frame = contentView.bounds
                contentView.addSubview(propsSegmentView)
            }
        })
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class SectionView: BackgroundView {
    
    init(frame: NSRect, title: String) {
        super.init(frame: frame)
        
        let separator = BackgroundView(frame: NSMakeRect(4, 0, bounds.width - 8, 2))
        separator.backgroundColor = NSColor.red
        addSubview(separator)
        
        let disclosure = NSButton()
        disclosure.title = ""
        disclosure.setButtonType(.pushOnPushOff)
        disclosure.bezelStyle = .disclosure
        disclosure.sizeToFit()
        disclosure.frame = NSMakeRect(8, 10, disclosure.frame.width, disclosure.frame.height)
        addSubview(disclosure)
        
        let titleLabel = NSTextField(frame: NSMakeRect(disclosure.frame.maxX + 2, 8, frame.width - disclosure.frame.maxX - 8, 24))
        titleLabel.stringValue = title
        titleLabel.isEditable = false
        titleLabel.isBezeled = false
        titleLabel.backgroundColor = NSColor.clear
        titleLabel.font = NSFont.boldSystemFont(ofSize: 12)
        addSubview(titleLabel)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class BaseSegmentView: BackgroundView {
    
    fileprivate var scrollView: ScrollView!
    
    init(frame: NSRect, model: SidebarModel) {
        super.init(frame: frame)
        
        scrollView = ScrollView(frame: self.bounds)
        scrollView.drawsBackground = false
        scrollView.autoresizingMask = [.width, .height]
        scrollView.visible <~ model.itemSelected
        addSubview(scrollView)
        
        let noSelectionLabel = labelField("No Selection")
        noSelectionLabel.font = NSFont.boldSystemFont(ofSize: 14.0)
        noSelectionLabel.alignment = .center
        noSelectionLabel.textColor = NSColor.darkGray
        noSelectionLabel.visible <~ model.itemNotSelected
        noSelectionLabel.sizeToFit()
        noSelectionLabel.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        var f = noSelectionLabel.frame
        f.origin.x = round(frame.midX - (f.width * 0.5))
        f.origin.y = round(frame.midY - (f.height * 0.5))
        noSelectionLabel.frame = f
        addSubview(noSelectionLabel)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private class CodeSegmentView: BaseSegmentView {
    
    init(frame: NSRect, model: DocModel) {
        super.init(frame: frame, model: model.sidebarModel)
        
        let textView = NSTextView()
        textView.frame.size = scrollView.contentSize
        textView.minSize.width = 0
        textView.minSize.height = scrollView.contentSize.height
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.drawsBackground = true
        textView.backgroundColor = .darkGray
        textView.textColor = .white
        textView.insertionPointColor = .white
        textView.isEditable = false
        
        textView.textContainer?.containerSize.width = scrollView.contentSize.width
        textView.textContainer?.containerSize.height = CGFloat.greatestFiniteMagnitude
        textView.textContainer?.widthTracksTextView = true
        textView.autoresizingMask = [ .width ]
        
        scrollView.documentView = textView
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private class PropsSegmentView: BaseSegmentView {
    
    init(frame: NSRect, model: DocModel) {
        super.init(frame: frame, model: model.sidebarModel)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private func labelField() -> TextField {
    let label = TextField()
    label.font = NSFont.systemFont(ofSize: 12.0)
    label.isBezeled = false
    label.isEditable = false
    label.isSelectable = false
    label.drawsBackground = false
    return label
}

private func labelField(_ text: String) -> TextField {
    let label = labelField()
    label.stringValue = text
    return label
}
