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

private let stepDuration: TimeInterval = 1.0

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    
    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var textView: TextView!
    @IBOutlet weak var previousButton: Button!
    @IBOutlet weak var nextButton: Button!
    @IBOutlet weak var replayButton: Button!
    @IBOutlet weak var tableContainer: NSView!
    
    private var input1View: RelationView!
    private var input2View: RelationView!
    private var joinView: RelationView!
    
    private var input1Arrow: ArrowView!
    private var input2Arrow: ArrowView!
    private var joinArrow: ArrowView!
    
    private var model: ViewModel!
    
    private let animating: MutableValueProperty<Bool> = mutableValueProperty(false)
    private var input1Changes: Int = 0
    private var input2Changes: Int = 0
    private var joinChanges: Int = 0
    
    private var orchestrateTimer: Timer?
    private var completionTimer: Timer?
    
    private var observerRemovals: [ObserverRemoval] = []

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        window.delegate = self

        // Initialize our view model
        model = ViewModel()
        
        // Configure the text view
        textView.textContainerInset = NSMakeSize(0, 5)
        textView.font = NSFont(name: "Menlo", size: 11)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4.0
        textView.defaultParagraphStyle = style
        
        // Configure the relation views
        let h: CGFloat = 120
        input1View = addRelationView(to: tableContainer, x: 40, y: 90, w: 240, h: h, name: "fruit", property: model.fruitsProperty, orderedAttrs: [Fruit.id, Fruit.name])
        input2View = addRelationView(to: tableContainer, x: 320, y: 90, w: 120, h: h, name: "selected_fruit_id", property: model.selectedFruitIDsProperty, orderedAttrs: [SelectedFruit.id])
        joinView = addRelationView(to: tableContainer, x: 40, y: 300, w: 240, h: h, name: "selected_fruit", property: model.selectedFruitsProperty, orderedAttrs: [Fruit.id, Fruit.name])

        // Add the arrow views
        let aw: CGFloat = 40
        let haw: CGFloat = aw * 0.5
        let ah: CGFloat = 64
        input1Arrow = addArrowView(to: tableContainer, x: input1View.frame.midX - haw, y: 2, w: aw, h: ah)
        input2Arrow = addArrowView(to: tableContainer, x: input2View.frame.midX - haw, y: 2, w: aw, h: ah)
        joinArrow = addArrowView(to: tableContainer, x: joinView.frame.midX - haw, y: 220, w: aw, h: ah)
        
        // Bind to the view model
        textView.text <~ model.changeDescription
        previousButton.disabled <~ not(previousEnabled)
        previousButton.clicks ~~> model.goToPreviousState
        nextButton.disabled <~ not(nextEnabled)
        nextButton.clicks ~~> model.goToNextState
        replayButton.disabled <~ not(replayEnabled)
        replayButton.clicks ~~> model.replayCurrentState
        
        // Observe the relation-based array properties so that we can orchestrate the animations
        func observe(_ property: ArrayProperty<RowArrayElement>, _ callback: @escaping ((Int) -> Void)) {
            let removal = property.signal.observe{ [weak self] event in
                guard let strongSelf = self else { return }
                switch event {
                case .beginPossibleAsyncChange:
                    // Enter animating state as soon as we see any change to a relation.  Also, start a timer that will
                    // fire and begin orchestrating animations after we've observed all changes on this runloop.
                    if !strongSelf.animating.value {
                        strongSelf.animating.change(true)
                        strongSelf.orchestrateTimer?.invalidate()
                        strongSelf.orchestrateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false, block: { _ in
                            strongSelf.orchestrateAnimations()
                        })
                    }
                case let .valueChanging(changes, _):
                    let validChanges = changes.filter{
                        switch $0 {
                        case .initial: return false
                        case .insert, .delete, .update, .move: return true
                        }
                    }
                    callback(validChanges.count)
                case .endPossibleAsyncChange:
                    break
                }
            }
            observerRemovals.append(removal)
        }
        observe(model.fruitsProperty, { [weak self] in self?.input1Changes += $0 })
        observe(model.selectedFruitIDsProperty, { [weak self] in self?.input2Changes += $0 })
        observe(model.selectedFruitsProperty, { [weak self] in self?.joinChanges += $0 })
    }
    
    deinit {
        observerRemovals.forEach{ $0() }
    }
    
    private func orchestrateAnimations() {
        Swift.print("ORCH!")
        var accumDelay: TimeInterval = 0.0

        func animate(_ arrow: ArrowView, _ view: RelationView, _ changeCount: Int) {
            if changeCount == 0 {
                return
            }
            
            arrow.animate(delay: accumDelay, duration: stepDuration)
            accumDelay += stepDuration
            
            view.animate(delay: accumDelay, duration: stepDuration)
            accumDelay += (stepDuration * TimeInterval(changeCount))
        }

        animate(input1Arrow, input1View, input1Changes)
        animate(input2Arrow, input2View, input2Changes)
        animate(joinArrow, joinView, joinChanges)
        
        orchestrateTimer?.invalidate()
        orchestrateTimer = nil

        // Reset counters when animations have completed
        Swift.print("SCHEDULING COMPLETION: \(accumDelay)")
        completionTimer = Timer.scheduledTimer(withTimeInterval: accumDelay + 0.5, repeats: false, block: { _ in
            Swift.print("DONE!")
            self.input1Changes = 0
            self.input2Changes = 0
            self.joinChanges = 0
            self.animating.change(false)
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
    
    private func addArrowView(to parent: NSView, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> ArrowView {
        let arrowView = ArrowView(frame: NSMakeRect(x, y, w, h))
        parent.addSubview(arrowView)
        return arrowView
    }

    private lazy var previousEnabled: ReadableProperty<Bool> = {
        return not(self.animating) *&& self.model.previousEnabled
    }()

    private lazy var nextEnabled: ReadableProperty<Bool> = {
        return not(self.animating) *&& self.model.nextEnabled
    }()
    
    private lazy var replayEnabled: ReadableProperty<Bool> = {
        return not(self.animating)
    }()
}
