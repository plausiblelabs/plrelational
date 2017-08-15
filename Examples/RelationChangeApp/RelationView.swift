//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelational
import PLRelationalBinding
import PLBindableControls

class RelationView: BackgroundView {

    private var rowViews: [NSView] = []
    private let startY: CGFloat = 26
    private let rowH: CGFloat = 24

    private let orderedAttrs: [Attribute]
    private let arrayProperty: ArrayProperty<RowArrayElement>
    private var arrayObserverRemoval: ObserverRemoval?

    init(frame: NSRect, relation: Relation, idAttr: Attribute, orderedAttrs: [Attribute]) {
        self.orderedAttrs = orderedAttrs
        self.arrayProperty = relation.arrayProperty(idAttr: idAttr, orderAttr: idAttr)
        
        super.init(frame: frame)
        
        backgroundColor = .white
        
        let headerView = labelRow(y: 0, fg: .darkGray, orderedAttrs.map{ $0.name })
        let sep = BackgroundView(frame: NSMakeRect(0, rowH - 1, frame.width, 1))
        sep.backgroundColor = .lightGray
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
    
    private func arrayChanged(_ arrayChanges: [ArrayChange<RowArrayElement>]) {
        
        func addRowView(_ elem: RowArrayElement) {
            let y = startY + (CGFloat(rowViews.count) * rowH)
            var labels: [String] = []
            for attr in orderedAttrs {
                labels.append(elem.data[attr].description)
            }
            let rowView = labelRow(y: y, fg: .black, labels)
            rowViews.append(rowView)
            addSubview(rowView)
        }
        
        // Record changes that were made to the array relative to its previous state
        for change in arrayChanges {
            switch change {
            case let .initial(elems):
                Swift.print("INITIAL: \(elems)")
                for elem in elems {
                    addRowView(elem)
                }
                
            case let .insert(index):
                Swift.print("INSERT: \(index)")
                // TODO: Don't append, insert
                addRowView(arrayProperty.elements[index])
                
            case let .delete(index):
                Swift.print("DELETE: \(index)")
                let rowView = rowViews.remove(at: index)
                rowView.removeFromSuperview()
                
            case let .update(index):
                Swift.print("UPDATE: \(index)")
                
            case .move:
                fatalError("Not yet implemented")
            }
        }
    }
    
    private func labelRow(y: CGFloat, fg: NSColor, _ labels: [String]) -> BackgroundView {
        let rowView = BackgroundView(frame: NSMakeRect(0, y, frame.width, rowH))
        let labelW = frame.width / CGFloat(labels.count)
        var x: CGFloat = 0
        for label in labels {
            let labelView = Label()
            labelView.textColor = fg
            labelView.stringValue = label
            labelView.sizeToFit()
            var labelFrame = labelView.frame
            labelFrame.origin.x = x + 4
            labelFrame.origin.y = round((rowH - labelFrame.height) * 0.5)
            labelFrame.size.width = labelW - 8
            labelView.frame = labelFrame
            rowView.addSubview(labelView)
            x += labelW
        }
        return rowView
    }
}
