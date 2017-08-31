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
    
    private var sourceView: StageView!
    private var resultView: StageView?
    private var resultLabel: Label?
    private var resultArrow: ArrowView?

    private var model: ViewModel!
    
    private var observerRemovals: [ObserverRemoval] = []
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        window.delegate = self
        
        // Initialize our view model
        model = ViewModel()

        let viewW: CGFloat = tableContainer.frame.width
        let viewH: CGFloat = 150
        sourceView = addStageView(to: tableContainer, x: 0, y: 20, w: viewW, h: viewH, name: "fruits", relation: model.fruits, property: model.fruitsProperty, orderedAttrs: [Fruit.id, Fruit.name, Fruit.quantity]).0
        
        let removal = sourceView.output.signal.observeSynchronousValueChanging{ output, _ in
            self.resultView?.removeFromSuperview()
            self.resultLabel?.removeFromSuperview()
            self.resultArrow?.removeFromSuperview()
            if let output = output {
                let (stageView, label) = self.addStageView(to: self.tableContainer, x: 0, y: 280, w: viewW, h: viewH, name: "result", relation: output.relation, property: output.arrayProperty, orderedAttrs: output.orderedAttrs)
                self.resultView = stageView
                self.resultLabel = label
                
                let aw: CGFloat = 40
                let haw: CGFloat = aw * 0.5
                let ah: CGFloat = 64
                let arrowX: CGFloat = (self.sourceView.relationW * 0.5) - haw
                let arrowW: CGFloat
                if output.combineActive {
                    arrowW = viewW - (arrowX * 2)
                } else {
                    arrowW = aw
                }
                self.resultArrow = self.addArrowView(to: self.tableContainer, x: arrowX, y: self.sourceView.frame.maxY + 10, w: arrowW, h: ah, dual: output.combineActive)
            }
        }
        observerRemovals.append(removal)
    }
    
    deinit {
        observerRemovals.forEach{ $0() }
    }
    
    private func addStageView(to parent: NSView, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
                              name: String, relation: Relation, property: ArrayProperty<RowArrayElement>, orderedAttrs: [Attribute]) -> (StageView, Label)
    {
        let stageView = StageView(frame: NSMakeRect(x, y, w, h), relation: relation, arrayProperty: property, orderedAttrs: orderedAttrs)
        parent.addSubview(stageView)
        
        let label = Label()
        label.stringValue = name
        label.sizeToFit()
        var labelFrame = label.frame
        labelFrame.origin.x = x + 4
        labelFrame.origin.y = y - labelFrame.height - 2
        label.frame = labelFrame
        parent.addSubview(label)
        
        return (stageView, label)
    }
    
    private func addArrowView(to parent: NSView, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, dual: Bool) -> ArrowView {
        let arrowView = ArrowView(frame: NSMakeRect(x, y, w, h), dual: dual)
        parent.addSubview(arrowView)
        return arrowView
    }
}
