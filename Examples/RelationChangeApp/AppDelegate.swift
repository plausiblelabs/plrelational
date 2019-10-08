//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelational
import PLRelationalBinding
import PLBindableControls

let codeFont = NSFont(name: "Menlo", size: 11)

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    
    private enum ChangeType {
        case insert
        case delete
        case update
    }
    
    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var codeTextView: ScrollingTextView!
    @IBOutlet weak var nextButton: Button!
    @IBOutlet weak var resetButton: Button!
    @IBOutlet weak var replayButton: Button!
    @IBOutlet weak var tableContainer: NSView!
    @IBOutlet weak var rawTextView: TextView!
    
    private var input1View: RelationView!
    private var input2View: RelationView!
    private var joinView: RelationView!
    
    private var input1Arrow: ArrowView!
    private var input2Arrow: ArrowView!
    private var joinArrow: ArrowView!
    
    private var model: ViewModel!
    
    private var input1Changes: [ChangeType] = []
    private var input2Changes: [ChangeType] = []
    private var joinChanges: [ChangeType] = []
    
    private var orchestrateTimer: Timer?
    private var completionTimer: Timer?
    
    private var observerRemovals: [ObserverRemoval] = []

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // XXX: We're not ready for dark mode yet
        if #available(macOS 10.14, *) {
            NSApp.appearance = NSAppearance(named: .aqua)
        }

        window.delegate = self

        // Initialize our view model
        model = ViewModel()
        
        // Configure the scrolling code text view
        let gradient = CAGradientLayer()
        gradient.anchorPoint = CGPoint(x: 0, y: 0)
        gradient.bounds = codeTextView.bounds
        gradient.colors = [NSColor.clear.cgColor, NSColor.white.cgColor, NSColor.white.cgColor]
        codeTextView.wantsLayer = true
        codeTextView.layer!.mask = gradient
        codeTextView.strings = model.stateDescriptions
        
        // Configure the relation views
        let viewW: CGFloat = 160
        let viewH: CGFloat = 120
        let halfPadX: CGFloat = 22
        let input1ViewX = round(tableContainer.bounds.midX - viewW - halfPadX)
        let input2ViewX = round(tableContainer.bounds.midX + halfPadX)
        let joinViewX = round(tableContainer.bounds.midX - (viewW * 0.5))
        input1View = addRelationView(to: tableContainer, x: input1ViewX, y: 90, w: viewW, h: viewH, name: "fruits", property: model.fruitsProperty, orderedAttrs: [Fruit.id, Fruit.name])
        input2View = addRelationView(to: tableContainer, x: input2ViewX, y: 90, w: viewW, h: viewH, name: "selectedFruitIDs", property: model.selectedFruitIDsProperty, orderedAttrs: [SelectedFruit.fruitID])
        joinView = addRelationView(to: tableContainer, x: joinViewX, y: 300, w: viewW, h: viewH, name: "selectedFruits", property: model.selectedFruitsProperty, orderedAttrs: [Fruit.id, Fruit.name])
        
        // Configure the raw changes text view
        rawTextView.font = codeFont
        rawTextView.textColor = .white
        rawTextView.textContainerInset = NSMakeSize(4, 8)

        // Add the arrow views
        let aw: CGFloat = 40
        let haw: CGFloat = aw * 0.5
        let ah: CGFloat = 64
        input1Arrow = addArrowView(to: tableContainer, x: input1View.frame.midX - haw, y: 2, w: aw, h: ah, dual: false)
        input2Arrow = addArrowView(to: tableContainer, x: input2View.frame.midX - haw, y: 2, w: aw, h: ah, dual: false)
        let joinArrowW = input2Arrow.frame.maxX - input1Arrow.frame.minX
        joinArrow = addArrowView(to: tableContainer, x: input1Arrow.frame.minX, y: 214, w: joinArrowW, h: ah, dual: true)
        
        // Bind to the view model
        codeTextView.index <~ model.stateIndex
        codeTextView.animated = true
        
        rawTextView.text <~ model.rawChangesText
        
        nextButton.disabled <~ model.animating
        nextButton.visible <~ model.nextVisible
        nextButton.string <~ model.nextButtonTitle
        nextButton.clicks ~~> model.goToNextState
        
        resetButton.disabled <~ model.animating
        resetButton.visible <~ model.resetVisible
        resetButton.clicks ~~> model.goToInitialState
        
        replayButton.disabled <~ not(model.replayEnabled)
        replayButton.clicks ~~> model.replayCurrentState
        
        // Observe the relation-based array properties so that we can orchestrate the animations
        func observe(_ property: ArrayProperty<RowArrayElement>, _ callback: @escaping (([ChangeType]) -> Void)) {
            let removal = property.signal.observe{ [weak self] event in
                guard let strongSelf = self else { return }
                switch event {
                case .beginPossibleAsyncChange:
                    // As soon as we see any change to a relation, start a timer that will fire and begin orchestrating
                    // animations after we've observed all changes queued on this runloop
                    if strongSelf.orchestrateTimer == nil {
                        strongSelf.orchestrateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false, block: { _ in
                            strongSelf.orchestrateAnimations()
                        })
                    }
                case let .valueChanging(changes, _):
                    let changeTypes = changes.compactMap{ (change) -> ChangeType? in
                        switch change {
                        case .initial: return nil
                        case .insert: return .insert
                        case .delete: return .delete
                        case .update, .move: return .update
                        }
                    }
                    callback(changeTypes)
                case .endPossibleAsyncChange:
                    break
                }
            }
            observerRemovals.append(removal)
        }
        observe(model.fruitsProperty, { [weak self] in self?.input1Changes.append(contentsOf: $0) })
        observe(model.selectedFruitIDsProperty, { [weak self] in self?.input2Changes.append(contentsOf: $0) })
        observe(model.selectedFruitsProperty, { [weak self] in self?.joinChanges.append(contentsOf: $0) })
    }
    
    deinit {
        observerRemovals.forEach{ $0() }
    }
    
    private func orchestrateAnimations() {
        let stepDuration = model.currentStepDuration
        var accumDelay: TimeInterval = 0.0

        func animate(_ arrow: ArrowView, _ view: RelationView, _ changes: [ChangeType]) {
            if changes.count == 0 {
                return
            }
            
            let arrowColor: NSColor
            let changeSet = Set(changes)
            if changeSet.count == 1 {
                switch changeSet.first! {
                case .insert:
                    arrowColor = .green
                case .delete:
                    arrowColor = .red
                case .update:
                    arrowColor = .orange
                }
            } else {
                arrowColor = .orange
            }
            
            arrow.animate(color: arrowColor, delay: accumDelay, duration: stepDuration)
            accumDelay += stepDuration
            
            view.animate(delay: accumDelay, duration: stepDuration)
            accumDelay += (stepDuration * TimeInterval(changes.count))
        }

        animate(input1Arrow, input1View, input1Changes)
        animate(input2Arrow, input2View, input2Changes)
        animate(joinArrow, joinView, joinChanges)
        
        orchestrateTimer?.invalidate()
        orchestrateTimer = nil

        // Reset counters when animations have completed
        completionTimer = Timer.scheduledTimer(withTimeInterval: accumDelay + 0.1, repeats: false, block: { _ in
            self.input1Changes = []
            self.input2Changes = []
            self.joinChanges = []
            self.model.prepareNextAnimation()
        })
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
    
    private func addArrowView(to parent: NSView, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, dual: Bool) -> ArrowView {
        let arrowView = ArrowView(frame: NSMakeRect(x, y, w, h), dual: dual)
        parent.addSubview(arrowView)
        return arrowView
    }
}
