//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelational
import PLRelationalBinding
import PLBindableControls

private let tableW: CGFloat = 240
private let tableH: CGFloat = 120

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    
    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var textView: TextView!
    @IBOutlet weak var previousButton: Button!
    @IBOutlet weak var nextButton: Button!
    @IBOutlet weak var tableContainer: NSView!
    
    private var model: ViewModel!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        window.delegate = self

        // Configure the text view
        textView.textContainerInset = NSMakeSize(0, 5)
        textView.font = NSFont(name: "Menlo", size: 10)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4.0
        textView.defaultParagraphStyle = style
        
        // Initialize our view model
        model = ViewModel()

        // Configure the relation views
        let h: CGFloat = 120
        addRelationView(to: tableContainer, x: 20, y: 40, w: 240, h: h, name: "fruit", relation: model.fruits, idAttr: Fruit.id, orderedAttrs: [Fruit.id, Fruit.name])
        addRelationView(to: tableContainer, x: 300, y: 40, w: 120, h: h, name: "selected_fruit_id", relation: model.selectedFruitIDs, idAttr: SelectedFruit._id, orderedAttrs: [SelectedFruit.id])
        addRelationView(to: tableContainer, x: 20, y: 220, w: 240, h: h, name: "selected_fruit", relation: model.selectedFruits, idAttr: SelectedFruit._id, orderedAttrs: [Fruit.id, Fruit.name])

        // Bind to the view model
        textView.text <~ model.changeDescription
        previousButton.disabled <~ not(model.previousEnabled)
        previousButton.clicks ~~> model.goToPreviousState
        nextButton.disabled <~ not(model.nextEnabled)
        nextButton.clicks ~~> model.goToNextState
    }
    
    private func addRelationView(to parent: NSView, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
                                 name: String, relation: Relation, idAttr: Attribute, orderedAttrs: [Attribute])
    {
        let relationView = RelationView(frame: NSMakeRect(x, y, w, h),relation: relation, idAttr: idAttr, orderedAttrs: orderedAttrs)
        relationView.wantsLayer = true
        relationView.layer!.cornerRadius = 8
        parent.addSubview(relationView)
        
        let label = Label()
        label.stringValue = name
        label.sizeToFit()
        var labelFrame = label.frame
        labelFrame.origin.x = x + 4
        labelFrame.origin.y = y - labelFrame.height - 2
        label.frame = labelFrame
        parent.addSubview(label)
    }
}

// XXX: Erases the gray line that gets drawn at the top of the table header
private class CustomHeaderView: NSTableHeaderView {
    override func draw(_ rect: NSRect) {
        super.draw(rect)
        NSColor.white.setFill()
        NSRectFill(NSMakeRect(0, 0, self.bounds.size.width, 1))
    }
}

struct RelationTableColumnModel: TableColumnModel {
    typealias ID = Attribute
    
    let identifier: Attribute
    var identifierString: String {
        return identifier.name
    }
    let title: String
    let width: CGFloat
}

typealias RelationTableViewModel = TableViewModel<RelationTableColumnModel, RowArrayElement>
typealias RelationTableView = TableView<RelationTableColumnModel, RowArrayElement>
