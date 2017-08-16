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
            Swift.print("RELATION VIEW ANIM")
            self.applyAnimations()
        })
    }

    private func applyAnimations() {
        
        func slide(_ labelRow: LabelRow, delta: CGFloat) {
            let labelRowView = labelRow.view
            
            var rowFrame = labelRowView.frame
            let startPoint = rowFrame.origin
            rowFrame.origin.y += delta
            let endPoint = rowFrame.origin
            labelRowView.frame = rowFrame
            
            CATransaction.begin()

            let animation = CABasicAnimation(keyPath: "position")
            animation.fromValue = NSValue(point: startPoint)
            animation.toValue = NSValue(point: endPoint)
            animation.duration = self.stepDuration
            //animation.beginTime = CACurrentMediaTime() + accumDelay
            animation.isRemovedOnCompletion = true
            labelRowView.layer!.add(animation, forKey: "position")
            
            CATransaction.commit()
        }
        
        func fade(_ labelRow: LabelRow, _ completion: (() -> Void)? = nil) {
            let labelRowView = labelRow.view
            let fadeIn = labelRowView.layer!.opacity < 1.0

            CATransaction.begin()
            
            CATransaction.setCompletionBlock({
                completion?()
            })

            labelRowView.layer!.opacity = fadeIn ? 1.0 : 0.0

            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = NSNumber(value: Float(fadeIn ? 0.0 : 1.0))
            animation.toValue = NSNumber(value: Float(fadeIn ? 1.0 : 0.0))
            animation.fillMode = kCAFillModeBoth
            animation.duration = self.stepDuration
            //animation.beginTime = CACurrentMediaTime() + accumDelay
            animation.isRemovedOnCompletion = true
            labelRowView.layer!.add(animation, forKey: "opacity")

            CATransaction.commit()
        }
        
        // Animate the change
        let change = changesToAnimate.removeFirst()
        switch change {
        case let .insert(index):
            Swift.print("INSERT: \(index)")
            // Slide existing elements (after the row to be inserted) down one spot
            for i in index..<labelRows.count {
                slide(labelRows[i], delta: rowH)
            }
            
            // Add the new row and fade it in
            addLabelRow(arrayProperty.elements[index], index, opacity: 0)
            fade(labelRows[index])
            
        case let .delete(index):
            Swift.print("DELETE: \(index)")
            // Fade out the row to be deleted, then remove it
            let labelRow = labelRows.remove(at: index)
            fade(labelRow, {
                labelRow.view.removeFromSuperview()
            })

            // Slide existing elements (after the deleted row) up one spot
            for i in index..<labelRows.count {
                slide(labelRows[i], delta: -rowH)
            }

        case let .update(index):
            Swift.print("UPDATE: \(index)")
            let labelRow = labelRows[index]
            let updatedRow = arrayProperty.elements[index].data
            for attr in updatedRow.scheme.attributes {
                if let cell = labelRow.cells[attr] {
                    let updatedValue = updatedRow[attr]
                    let updatedString = updatedValue.description
                    if updatedString != cell.string {
                        // TODO: Animate
                        cell.string = updatedString
                        cell.label.stringValue = updatedString
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
                Swift.print("INITIAL: \(elems)")
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

            cells[attr] = LabelCell(attribute: attr, string: string, label: labelView)
            
            rowView.addSubview(labelView)
            x += labelW
        }

        return LabelRow(view: rowView, cells: cells)
    }
    
    private class LabelRow {
        let view: BackgroundView
        let cells: [Attribute: LabelCell]
        
        init(view: BackgroundView, cells: [Attribute: LabelCell]) {
            self.view = view
            self.cells = cells
        }
    }
    
    private class LabelCell {
        let attribute: Attribute
        var string: String
        let label: Label
        
        init(attribute: Attribute, string: String, label: Label) {
            self.attribute = attribute
            self.string = string
            self.label = label
        }
    }
}
