//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelational
import PLRelationalBinding
import PLBindableControls

class StageView: BackgroundView {

    private enum FilterOp {
        case none
        case selectEq
        case selectMin
        case selectMax
        case min
        case max
        case count
        
        var needsAttribute: Bool {
            switch self {
            case .selectEq, .selectMin, .selectMax, .min, .max:
                return true
            case .none, .count:
                return false
            }
        }

        var needsValue: Bool {
            switch self {
            case .selectEq:
                return true
            default:
                return false
            }
        }

        var displayName: String {
            switch self {
            case .none: return "No Filter"
            case .selectEq: return "select"
            case .selectMin: return "selectMin"
            case .selectMax: return "selectMax"
            case .min: return "min"
            case .max: return "max"
            case .count: return "count"
            }
        }
    }
    
    private enum CombineOp {
        case none
        case join
        
        var displayName: String {
            switch self {
            case .none: return "No Combine"
            case .join: return "join"
            }
        }
    }

    private struct RelationModel {
        let relation: Relation
        let arrayProperty: ArrayProperty<RowArrayElement>
        let orderedAttrs: [Attribute]
    }
    
    struct Output {
        let relation: Relation
        let arrayProperty: ArrayProperty<RowArrayElement>
        let orderedAttrs: [Attribute]
        let combineActive: Bool
    }

    private let input1: RelationModel
    private let input2: RelationModel
    
    private var filterOpPopup: PopUpButton<FilterOp>!
    private var filterAttrPopup: PopUpButton<Attribute>!
    private var filterValueField: TextField!
    
    private var combineOpPopup: PopUpButton<CombineOp>!
    
    // XXX
    var relationW: CGFloat!
    
    init(frame: NSRect, relation: Relation, arrayProperty: ArrayProperty<RowArrayElement>, orderedAttrs: [Attribute]) {
        self.input1 = RelationModel(relation: relation, arrayProperty: arrayProperty, orderedAttrs: orderedAttrs)
        // TODO: Make this configurable
        let input2Relation = MakeRelation(["id"], [1])
        self.input2 = RelationModel(relation: input2Relation, arrayProperty: input2Relation.arrayProperty(idAttr: "id", orderAttr: "id"), orderedAttrs: ["id"])
        
        super.init(frame: frame)

        let popupH: CGFloat = 24
        
        let filterTopPad: CGFloat = 10
        let filterH: CGFloat = 40
        let combineW: CGFloat = 140
        let relationW: CGFloat = round(frame.width - combineW) * 0.5
        let relationH: CGFloat = frame.height - filterH
        self.relationW = relationW
        
        let filterFrame = NSMakeRect(0, frame.height - filterH - filterTopPad, relationW, filterH + filterTopPad)
        let filterView = BackgroundView(frame: filterFrame)
        //filterView.backgroundColor = NSColor(red: 37.0/255.0, green: 170.0/255.0, blue: 225.0/255.0, alpha: 1.0)
        filterView.backgroundColor = NSColor(white: 0.7, alpha: 1.0)
        filterView.wantsLayer = true
        filterView.layer!.cornerRadius = 8
        self.addSubview(filterView)
        
        let combineFrame = NSMakeRect(relationW, 16, combineW, relationH - 32)
        let combineView = BackgroundView(frame: combineFrame)
        //combineView.backgroundColor = NSColor(white: 0.7, alpha: 1.0)
        combineView.wantsLayer = true
        combineView.layer!.addSublayer(curvyBg(combineView.bounds))
        self.addSubview(combineView)
        
        let input1Frame = NSMakeRect(0, 0, relationW, relationH)
        let input1View = RelationView(frame: input1Frame, arrayProperty: input1.arrayProperty, orderedAttrs: input1.orderedAttrs)
        input1View.wantsLayer = true
        input1View.layer!.cornerRadius = 8
        self.addSubview(input1View)

        let input2Frame = NSMakeRect(relationW + combineW, 0, relationW, relationH)
        let input2View = RelationView(frame: input2Frame, arrayProperty: input2.arrayProperty, orderedAttrs: input2.orderedAttrs)
        input2View.wantsLayer = true
        input2View.layer!.cornerRadius = 8
        self.addSubview(input2View)

        filterOpPopup = PopUpButton(frame: NSMakeRect(10, filterFrame.height - 32, 100, popupH), pullsDown: false)
        filterOpPopup.items <~ self.filterOpMenuItems
        filterOpPopup.selectedObject <~> self.selectedFilterOp
        filterView.addSubview(filterOpPopup)
        
        filterAttrPopup = PopUpButton(frame: NSMakeRect(120, filterFrame.height - 32, 90, popupH), pullsDown: false)
        filterAttrPopup.visible <~ self.filterAttrPopupVisible
        filterAttrPopup.items <~ self.filterAttrMenuItems
        filterAttrPopup.selectedObject <~> self.selectedFilterAttr
        filterView.addSubview(filterAttrPopup)
        
        filterValueField = TextField(frame: NSMakeRect(220, filterFrame.height - 32, 70, 22))
        filterValueField.visible <~ self.filterValueFieldVisible
        filterValueField.string <~> filterValue
        filterView.addSubview(filterValueField)
        
        combineOpPopup = PopUpButton(frame: NSMakeRect(10, combineView.bounds.midY - (popupH * 0.5), combineW - 20, popupH), pullsDown: false)
        combineOpPopup.items <~ self.combineOpMenuItems
        combineOpPopup.selectedObject <~> self.selectedCombineOp
        combineView.addSubview(combineOpPopup)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private lazy var filterOpMenuItems: ReadableProperty<[MenuItem<FilterOp>]> = {
        var items = [MenuItem<FilterOp>]()
        func addItem(_ op: FilterOp) {
            items.append(MenuItem(.normal(MenuItemContent(object: op, title: constantValueProperty(op.displayName), image: nil))))
        }

        addItem(.none)
        addItem(.selectEq)
        addItem(.selectMin)
        addItem(.selectMax)
        addItem(.min)
        addItem(.max)
        addItem(.count)
        
        return constantValueProperty(items)
    }()

    private lazy var selectedFilterOp: MutableValueProperty<FilterOp?> = {
        return mutableValueProperty(FilterOp.none, { _ in self.selectedCombineOp.change(CombineOp.none) })
    }()

    private lazy var filterAttrPopupVisible: ReadableProperty<Bool> = {
        return self.filterOpPopup.selectedObject.map{ $0?.needsAttribute ?? false }
    }()
    
    private lazy var filterAttrMenuItems: ReadableProperty<[MenuItem<Attribute>]> = {
        let items = self.input1.orderedAttrs.map{
            return MenuItem(.normal(MenuItemContent(object: $0, title: constantValueProperty($0.description), image: nil)))
        }
        return constantValueProperty(items)
    }()
    
    private lazy var selectedFilterAttr: ReadWriteProperty<Attribute?> = {
        return mutableValueProperty(self.input1.orderedAttrs.first!)
    }()
    
    private lazy var filterValueFieldVisible: ReadableProperty<Bool> = {
        return self.filterOpPopup.selectedObject.map{ $0?.needsValue ?? false }
    }()
    
    private lazy var filterValue: ReadWriteProperty<String> = {
        return mutableValueProperty("")
    }()
    
    private lazy var combineOpMenuItems: ReadableProperty<[MenuItem<CombineOp>]> = {
        var items = [MenuItem<CombineOp>]()
        func addItem(_ op: CombineOp) {
            items.append(MenuItem(.normal(MenuItemContent(object: op, title: constantValueProperty(op.displayName), image: nil))))
        }
        
        addItem(.none)
        addItem(.join)
        
        return constantValueProperty(items)
    }()
    
    private lazy var selectedCombineOp: MutableValueProperty<CombineOp?> = {
        return mutableValueProperty(CombineOp.none, { _ in self.selectedFilterOp.change(FilterOp.none) })
    }()
    
    private lazy var filterOutput: ReadableProperty<Output?> = {
        // TODO: We could use a `zip3`
        let opAndAttr: ReadableProperty<(FilterOp?, Attribute?)> = zip(self.selectedFilterOp, self.selectedFilterAttr)
        return zip(opAndAttr, self.filterValue).map{
            let op = $0.0.0
            let attr = $0.0.1
            let value = $0.1

            let input1Relation = self.input1.relation
            let idAttr: Attribute
            let newRelation: Relation
            let orderedAttrs: [Attribute]
            switch op! {
            case .none:
                return nil
            case .selectEq:
                // TODO: Explicitly state which attribute should be treated as the unique ID
                idAttr = self.input1.orderedAttrs.first!
                newRelation = input1Relation.select(attr! *== RelationValue(value))
                orderedAttrs = self.input1.orderedAttrs
            case .selectMin:
                idAttr = self.input1.orderedAttrs.first!
                newRelation = input1Relation.select(min: attr!)
                orderedAttrs = self.input1.orderedAttrs
            case .selectMax:
                idAttr = self.input1.orderedAttrs.first!
                newRelation = input1Relation.select(max: attr!)
                orderedAttrs = self.input1.orderedAttrs
            case .min:
                idAttr = attr!
                newRelation = input1Relation.min(attr!)
                orderedAttrs = [idAttr]
            case .max:
                idAttr = attr!
                newRelation = input1Relation.max(attr!)
                orderedAttrs = [idAttr]
            case .count:
                idAttr = "count"
                newRelation = input1Relation.count()
                orderedAttrs = [idAttr]
            }
            
            let newArrayProperty = newRelation.arrayProperty(idAttr: idAttr, orderAttr: idAttr)
            return Output(relation: newRelation, arrayProperty: newArrayProperty, orderedAttrs: orderedAttrs, combineActive: false)
        }
    }()
    
    private lazy var combineOutput: ReadableProperty<Output?> = {
        return self.selectedCombineOp
            .map {
                switch $0! {
                case .none:
                    return nil
                case .join:
                    // TODO: Explicitly state which attribute should be treated as the unique ID
                    let idAttr = self.input1.orderedAttrs.first!
                    let newRelation = self.input1.relation.join(self.input2.relation)
                    let newArrayProperty = newRelation.arrayProperty(idAttr: idAttr, orderAttr: idAttr)
                    return Output(relation: newRelation, arrayProperty: newArrayProperty, orderedAttrs: self.input1.orderedAttrs, combineActive: true)
                }
            }
    }()
    
    lazy var output: ReadableProperty<Output?> = {
        return zip(self.filterOutput, self.combineOutput)
            .map{
                return $0.0 ?? $0.1
            }
    }()
}

private extension Relation {
    func select(min attribute: Attribute) -> Relation {
        let min = self.min(attribute)
        return min.join(self)
    }
    
    func select(max attribute: Attribute) -> Relation {
        let max = self.max(attribute)
        return max.join(self)
    }
}

private func curvyBg(_ b: CGRect) -> CAShapeLayer {

    func curvyPath() -> NSBezierPath {
        let yOff: CGFloat = 16
        let p = NSBezierPath()
        p.move(to: CGPoint.zero)
        p.curve(to: CGPoint(x: b.maxX, y: b.minY), controlPoint1: CGPoint(x: b.minX, y: b.midY - yOff), controlPoint2: CGPoint(x: b.maxX, y: b.midY - yOff))
        p.line(to: CGPoint(x: b.maxX, y: b.maxY))
        p.curve(to: CGPoint(x: b.minX, y: b.maxY), controlPoint1: CGPoint(x: b.maxX, y: b.midY + yOff), controlPoint2: CGPoint(x: b.minX, y: b.midY + yOff))
        p.line(to: CGPoint(x: b.minX, y: b.minY))
        return p
    }
    
    let l = CAShapeLayer()
    l.path = curvyPath().cgPath
    l.fillColor = NSColor(white: 0.7, alpha: 1.0).cgColor
    return l
}
