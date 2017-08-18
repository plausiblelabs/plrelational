//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelationalBinding
import PLBindableControls

class TextView: BackgroundView {

    private var labelContainer: BackgroundView!

    var strings: [String] = [] {
        didSet {
            let labelPadX: CGFloat = 4
            let labelH = self.bounds.height * 0.5
            let labelW = self.bounds.width - (labelPadX * 2)
            let containerH = CGFloat(strings.count) * labelH
            labelContainer?.removeFromSuperview()
            labelContainer = BackgroundView(frame: NSMakeRect(0, 0, self.bounds.width, containerH))
            labelContainer.backgroundColor = .clear
            addSubview(labelContainer)

            var y: CGFloat = 0
            for string in strings {
                let label = Label(frame: NSMakeRect(labelPadX, 0, labelW, labelH))
                label.font = NSFont(name: "Menlo", size: 11)
                label.stringValue = string
                let actualH = label.cell!.cellSize(forBounds: label.frame).height
                var labelFrame = label.frame
                labelFrame.origin.y = y + round((labelH - actualH) * 0.5)
                label.frame = labelFrame
                labelContainer.addSubview(label)
                y += labelH
            }
            
            scrollToIndex(0)
        }
    }
    
    var animated: Bool = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        setUp()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    func setUp() {
        self.backgroundColor = .white
    }

    lazy var index: BindableProperty<Int> = WriteOnlyProperty(set: { [weak self] in
        self?.scrollToIndex($0.0)
    })
    
    private func scrollToIndex(_ index: Int) {
        let labelH = self.bounds.height * 0.5
        
        var containerFrame = labelContainer.frame
        let startPoint = containerFrame.origin
        containerFrame.origin.y = labelH - (CGFloat(index) * labelH)
        let endPoint = containerFrame.origin
        
        if animated {
            CATransaction.begin()
            
            CATransaction.setCompletionBlock({
                self.labelContainer.frame = containerFrame
            })
            
            let animation = CABasicAnimation(keyPath: "position")
            animation.fromValue = NSValue(point: startPoint)
            animation.toValue = NSValue(point: endPoint)
            animation.duration = 0.5
            animation.isRemovedOnCompletion = true
            labelContainer.layer!.add(animation, forKey: "position")
            
            CATransaction.commit()
        } else {
            self.labelContainer.frame = containerFrame
        }
    }
}
