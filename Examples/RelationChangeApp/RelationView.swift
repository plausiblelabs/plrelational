//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelational
import PLRelationalBinding
import PLBindableControls

class RelationView: BackgroundView {

    private var labelRows: [LabelRow] = []
    private let startY: CGFloat = 26
    private let rowH: CGFloat = 24

    private let orderedAttrs: [Attribute]
    private let arrayProperty: ArrayProperty<RowArrayElement>
    private var arrayObserverRemoval: ObserverRemoval?

    private var changesToAnimate: [ArrayChange<RowArrayElement>] = []
    private var stepDuration: TimeInterval = 0
    
    init(frame: NSRect, arrayProperty: ArrayProperty<RowArrayElement>, orderedAttrs: [Attribute]) {
        self.arrayProperty = arrayProperty
        self.orderedAttrs = orderedAttrs
        
        super.init(frame: frame)
        
        backgroundColor = .white
        
        let headerRow = labelRow(y: 0, fg: .darkGray, orderedAttrs.map{ ($0, $0.name) })
        let headerView = headerRow.view
        let sep = BackgroundView(frame: NSMakeRect(0, rowH - 1, frame.width, 1))
        sep.backgroundColor = NSColor(white: 0.9, alpha: 1.0)
        headerView.addSubview(sep)
        addSubview(headerView)

        arrayObserverRemoval = arrayProperty.signal.observeValueChanging{ [weak self] changes, _ in
            self?.arrayChanged(changes)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        arrayObserverRemoval?()
    }
    
    func animate(delay: TimeInterval, duration: TimeInterval) {
        self.stepDuration = duration
        
        Timer.scheduledTimer(withTimeInterval: delay, repeats: false, block: { _ in
            self.applyAnimations()
        })
    }

    private func applyAnimations() {
        let slideDuration: TimeInterval = self.stepDuration * 0.3

        // Animate the change
        let change = changesToAnimate.removeFirst()
        switch change {
        case let .insert(index):
            // Slide existing elements (after the row to be inserted) down one spot
            for i in index..<labelRows.count {
                labelRows[i].slide(delta: rowH, delay: 0.0, duration: slideDuration)
            }
            
            // Add the new row and fade it in
            addLabelRow(arrayProperty.elements[index], index, opacity: 0)
            labelRows[index].fade(duration: self.stepDuration)
            
        case let .delete(index):
            // Fade out the row to be deleted, then remove it
            let labelRow = labelRows.remove(at: index)
            labelRow.fade(duration: self.stepDuration, completion: {
                labelRow.view.removeFromSuperview()
            })

            // Slide existing elements (after the deleted row) up one spot
            let slideDelay = self.stepDuration - slideDuration
            for i in index..<labelRows.count {
                labelRows[i].slide(delta: -rowH, delay: slideDelay, duration: slideDuration)
            }

        case let .update(index):
            let labelRow = labelRows[index]
            let updatedRow = arrayProperty.elements[index].data
            for attr in updatedRow.scheme.attributes {
                if let cell = labelRow.cells[attr] {
                    let updatedValue = updatedRow[attr]
                    let updatedString = updatedValue.description
                    if updatedString != cell.string {
                        // Fade to the new string
                        cell.animate(to: updatedString, delay: 0, duration: stepDuration)
                    }
                }
            }
            
        case .move:
            fatalError("Not yet implemented")

        case .initial:
            fatalError("Unexpected initial change")
        }

        if changesToAnimate.count > 0 {
            // Schedule the next change to be animated
            Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: false, block: { _ in
                self.applyAnimations()
            })
        }
    }

    private func arrayChanged(_ arrayChanges: [ArrayChange<RowArrayElement>]) {
        // Record changes that were made to the array relative to its previous state
        for change in arrayChanges {
            switch change {
            case let .initial(elems):
                for (index, elem) in elems.enumerated() {
                    addLabelRow(elem, index, opacity: 1)
                }
                
            default:
                changesToAnimate.append(change)
            }
        }
    }

    private func addLabelRow(_ elem: RowArrayElement, _ index: Int, opacity: Float) {
        let y = startY + (CGFloat(index) * rowH)
        let row = labelRow(y: y, fg: .black, orderedAttrs.map{ ($0, elem.data[$0].description) })
        labelRows.insert(row, at: index)
        row.view.wantsLayer = true
        row.view.layer!.opacity = opacity
        addSubview(row.view)
    }
    
    private func labelRow(y: CGFloat, fg: NSColor, _ attrStrings: [(Attribute, String)]) -> LabelRow {
        let rowView = BackgroundView(frame: NSMakeRect(0, y, frame.width, rowH))
        let labelW = frame.width / CGFloat(attrStrings.count)
        var x: CGFloat = 0
        
        var cells = [Attribute: LabelCell]()
        for (attr, string) in attrStrings {
            let labelView = Label()
            labelView.textColor = fg
            labelView.stringValue = string
            labelView.sizeToFit()
            
            var labelFrame = labelView.frame
            labelFrame.origin.x = x + 4
            labelFrame.origin.y = round((rowH - labelFrame.height) * 0.5)
            labelFrame.size.width = labelW - 8
            labelView.frame = labelFrame
            rowView.addSubview(labelView)

            cells[attr] = LabelCell(attribute: attr, string: string, label: labelView)
            
            x += labelW
        }

        return LabelRow(view: rowView, cells: cells)
    }
    
    private class LabelRow {
        let view: BackgroundView
        let cells: [Attribute: LabelCell]
        var highlightLayer: CAShapeLayer?
        
        init(view: BackgroundView, cells: [Attribute: LabelCell]) {
            self.view = view
            self.cells = cells
        }
        
        func slide(delta: CGFloat, delay: TimeInterval, duration: TimeInterval) {
            var rowFrame = view.frame
            let startPoint = rowFrame.origin
            rowFrame.origin.y += delta
            let endPoint = rowFrame.origin
            
            CATransaction.begin()
            
            CATransaction.setCompletionBlock({
                self.view.frame = rowFrame
            })

            let animation = CABasicAnimation(keyPath: "position")
            animation.fromValue = NSValue(point: startPoint)
            animation.toValue = NSValue(point: endPoint)
            animation.duration = duration
            animation.beginTime = CACurrentMediaTime() + delay
            animation.isRemovedOnCompletion = true
            view.layer!.add(animation, forKey: "position")
            
            CATransaction.commit()
        }
        
        func fade(duration: TimeInterval, completion: (() -> Void)? = nil) {
            let fadeIn = view.layer!.opacity < 1.0
            
            func addLayer() -> CAShapeLayer {
                let l = CAShapeLayer()
                l.path = NSBezierPath(roundedRect: view.bounds.insetBy(dx: 2, dy: 2), xRadius: 4, yRadius: 4).cgPath
                self.view.wantsLayer = true
                self.view.layer!.addSublayer(l)
                self.view.layer!.masksToBounds = false
                return l
            }
            
            if highlightLayer == nil {
                highlightLayer = addLayer()
            }
            let color: NSColor = fadeIn ? .green : .red
            highlightLayer!.fillColor = color.withAlphaComponent(0.3).cgColor
            highlightLayer!.opacity = 0.0
            
            func addHighlightAnimation() {
                let animation = CABasicAnimation(keyPath: "opacity")
                animation.fromValue = NSNumber(value: Float(0.0))
                animation.toValue = NSNumber(value: Float(1.0))
                animation.duration = duration * 0.6
                animation.autoreverses = true
                animation.repeatCount = 1
                animation.isRemovedOnCompletion = true
                highlightLayer!.add(animation, forKey: "opacity")
            }

            func addFadeAnimation() {
                view.layer!.opacity = fadeIn ? 1.0 : 0.0
                
                let animation = CABasicAnimation(keyPath: "opacity")
                animation.fromValue = NSNumber(value: Float(fadeIn ? 0.0 : 1.0))
                animation.toValue = NSNumber(value: Float(fadeIn ? 1.0 : 0.0))
                animation.fillMode = kCAFillModeBoth
                animation.duration = duration
                animation.isRemovedOnCompletion = true
                view.layer!.add(animation, forKey: "opacity")
            }
            
            CATransaction.begin()
            
            CATransaction.setCompletionBlock({
                completion?()
            })
            
            addHighlightAnimation()
            addFadeAnimation()
            
            CATransaction.commit()
        }
    }
    
    private class LabelCell {
        let attribute: Attribute
        var string: String
        let label: Label
        let oldStringLabel: Label
        var highlightLayer: CALayer?
        
        init(attribute: Attribute, string: String, label: Label) {
            self.attribute = attribute
            self.string = string
            self.label = label
            
            self.oldStringLabel = Label(frame: label.frame)
            oldStringLabel.backgroundColor = .white
            oldStringLabel.drawsBackground = true
            oldStringLabel.wantsLayer = true
            oldStringLabel.layer!.opacity = 0.0
            label.superview!.addSubview(oldStringLabel)
        }
        
        func animate(to newString: String, delay: TimeInterval, duration: TimeInterval) {
            // Capture the current string
            let oldString = self.string
            
            // Set the new string immediately
            self.string = newString
            self.label.stringValue = newString
            
            func addHighlightLayer(_ color: NSColor) -> CAShapeLayer {
                let l = CAShapeLayer()
                l.path = NSBezierPath(roundedRect: label.frame.insetBy(dx: -2, dy: -2), xRadius: 8, yRadius: 8).cgPath
                l.fillColor = NSColor.clear.cgColor
                l.strokeColor = color.cgColor
                l.lineWidth = 2
                self.label.superview!.layer!.addSublayer(l)
                self.label.superview!.layer!.masksToBounds = false
                return l
            }
            
            func addHighlightAnimation() {
                let animation = CABasicAnimation(keyPath: "opacity")
                animation.fromValue = NSNumber(value: Float(0.0))
                animation.toValue = NSNumber(value: Float(1.0))
                animation.duration = duration * 0.5
                animation.beginTime = CACurrentMediaTime() + delay
                animation.autoreverses = true
                animation.repeatCount = 1
                animation.isRemovedOnCompletion = true
                highlightLayer!.add(animation, forKey: "opacity")
            }
            
            func addOldStringAnimation() {
                let animation = CABasicAnimation(keyPath: "opacity")
                animation.fromValue = NSNumber(value: Float(1.0))
                animation.toValue = NSNumber(value: Float(0.0))
                animation.duration = duration
                animation.beginTime = CACurrentMediaTime() + delay
                animation.fillMode = kCAFillModeBoth
                animation.isRemovedOnCompletion = false
                oldStringLabel.layer!.add(animation, forKey: "opacity")
            }
            
            // Prepare the layers
            if highlightLayer == nil {
                highlightLayer = addHighlightLayer(.orange)
            }
            highlightLayer!.opacity = 0.0
            
            oldStringLabel.stringValue = oldString
            oldStringLabel.layer!.opacity = 1.0

            CATransaction.begin()

            addHighlightAnimation()
            addOldStringAnimation()
            
            CATransaction.commit()
        }
    }
}
