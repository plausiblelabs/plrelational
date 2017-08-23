//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelational
import PLRelationalBinding
import PLBindableControls

private let tableW: CGFloat = 360
private let tableH: CGFloat = 120

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    
    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var tableContainer: NSView!
    
    private var sourceView: RelationView!

    private var model: ViewModel!
    
    private var observerRemovals: [ObserverRemoval] = []
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        window.delegate = self
        
        // Initialize our view model
        model = ViewModel()

        let viewW: CGFloat = 320
        let viewH: CGFloat = 120
        sourceView = addRelationView(to: tableContainer, x: 40, y: 40, w: viewW, h: viewH, name: "fruits", property: model.fruitsProperty, orderedAttrs: [Fruit.id, Fruit.name, Fruit.quantity])
    }
    
    deinit {
        observerRemovals.forEach{ $0() }
    }
    
    private func addRelationView(to parent: NSView, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
                                 name: String, property: ArrayProperty<RowArrayElement>, orderedAttrs: [Attribute]) -> RelationView
    {
        let relationView = RelationView(frame: NSMakeRect(x, y, w, h), arrayProperty: property, orderedAttrs: orderedAttrs)
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
        
        return relationView
    }
}
