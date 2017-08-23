//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelational
import PLRelationalBinding
import PLBindableControls

class StageView: BackgroundView {

    enum Op {
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
    
    struct Output {
        let relation: Relation
        let arrayProperty: ArrayProperty<RowArrayElement>
        let orderedAttrs: [Attribute]
    }
    
    private let relation: Relation
    private let arrayProperty: ArrayProperty<RowArrayElement>
    private let orderedAttrs: [Attribute]

    private var opPopup: PopUpButton<Op>!
    private var attrPopup: PopUpButton<Attribute>!
    private var valueField: TextField!
    
    init(frame: NSRect, relation: Relation, arrayProperty: ArrayProperty<RowArrayElement>, orderedAttrs: [Attribute]) {
        self.relation = relation
        self.arrayProperty = arrayProperty
        self.orderedAttrs = orderedAttrs
        
        super.init(frame: frame)
        
        let filterTopPad: CGFloat = 10
        let filterH: CGFloat = 40
        let filterFrame = NSMakeRect(0, frame.height - filterH - filterTopPad, frame.width, filterH + filterTopPad)
        let filterView = BackgroundView(frame: filterFrame)
        //filterView.backgroundColor = NSColor(red: 37.0/255.0, green: 170.0/255.0, blue: 225.0/255.0, alpha: 1.0)
        filterView.backgroundColor = NSColor(white: 0.7, alpha: 1.0)
        filterView.wantsLayer = true
        filterView.layer!.cornerRadius = 8
        self.addSubview(filterView)
        
        let relationFrame = NSMakeRect(0, 0, frame.width, frame.height - filterH)
        let relationView = RelationView(frame: relationFrame, arrayProperty: arrayProperty, orderedAttrs: orderedAttrs)
        relationView.wantsLayer = true
        relationView.layer!.cornerRadius = 8
        self.addSubview(relationView)

        opPopup = PopUpButton(frame: NSMakeRect(10, filterFrame.height - 32, 100, 24), pullsDown: false)
        opPopup.items <~ self.opMenuItems
        opPopup.selectedObject <~> self.selectedOp
        filterView.addSubview(opPopup)
        
        attrPopup = PopUpButton(frame: NSMakeRect(120, filterFrame.height - 32, 90, 24), pullsDown: false)
        attrPopup.visible <~ self.attrPopupVisible
        attrPopup.items <~ self.attrMenuItems
        attrPopup.selectedObject <~> self.selectedAttr
        filterView.addSubview(attrPopup)
        
        valueField = TextField(frame: NSMakeRect(220, filterFrame.height - 32, 80, 22))
        valueField.visible <~ self.valueFieldVisible
        valueField.string <~> value
        filterView.addSubview(valueField)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private lazy var opMenuItems: ReadableProperty<[MenuItem<Op>]> = {
        var items = [MenuItem<Op>]()
        func addItem(_ op: Op) {
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

    private lazy var selectedOp: ReadWriteProperty<Op?> = {
        return mutableValueProperty(Op.none)
    }()

    private lazy var attrPopupVisible: ReadableProperty<Bool> = {
        return self.opPopup.selectedObject.map{ $0?.needsAttribute ?? false }
    }()
    
    private lazy var attrMenuItems: ReadableProperty<[MenuItem<Attribute>]> = {
        let items = self.orderedAttrs.map{
            return MenuItem(.normal(MenuItemContent(object: $0, title: constantValueProperty($0.description), image: nil)))
        }
        return constantValueProperty(items)
    }()
    
    private lazy var selectedAttr: ReadWriteProperty<Attribute?> = {
        return mutableValueProperty(self.orderedAttrs.first!)
    }()
    
    private lazy var valueFieldVisible: ReadableProperty<Bool> = {
        return self.opPopup.selectedObject.map{ $0?.needsValue ?? false }
    }()
    
    private lazy var value: ReadWriteProperty<String> = {
        return mutableValueProperty("")
    }()
    
    lazy var output: ReadableProperty<Output?> = {
        // TODO: We could use a `zip3`
        let opAndAttr: ReadableProperty<(Op?, Attribute?)> = zip(self.selectedOp, self.selectedAttr)
        return zip(opAndAttr, self.value).map{
            let op = $0.0.0
            let attr = $0.0.1
            let value = $0.1
            
            switch op! {
            case .none:
                return nil
            case .selectEq:
                // TODO: Explicitly state which attribute should be treated as the unique ID
                let idAttr = self.orderedAttrs.first!
                let newRelation = self.relation.select(attr! *== RelationValue(value))
                let newArrayProperty = newRelation.arrayProperty(idAttr: idAttr, orderAttr: idAttr)
                return Output(relation: newRelation, arrayProperty: newArrayProperty, orderedAttrs: self.orderedAttrs)
            case .selectMin:
                let idAttr = self.orderedAttrs.first!
                let newRelation = self.relation.select(min: attr!)
                let newArrayProperty = newRelation.arrayProperty(idAttr: idAttr, orderAttr: idAttr)
                return Output(relation: newRelation, arrayProperty: newArrayProperty, orderedAttrs: self.orderedAttrs)
            case .selectMax:
                let idAttr = self.orderedAttrs.first!
                let newRelation = self.relation.select(max: attr!)
                let newArrayProperty = newRelation.arrayProperty(idAttr: idAttr, orderAttr: idAttr)
                return Output(relation: newRelation, arrayProperty: newArrayProperty, orderedAttrs: self.orderedAttrs)
            case .min:
                let idAttr = attr!
                let newRelation = self.relation.min(attr!)
                let newArrayProperty = newRelation.arrayProperty(idAttr: idAttr, orderAttr: idAttr)
                return Output(relation: newRelation, arrayProperty: newArrayProperty, orderedAttrs: [idAttr])
            case .max:
                let idAttr = attr!
                let newRelation = self.relation.max(attr!)
                let newArrayProperty = newRelation.arrayProperty(idAttr: idAttr, orderAttr: idAttr)
                return Output(relation: newRelation, arrayProperty: newArrayProperty, orderedAttrs: [idAttr])
            case .count:
                let idAttr: Attribute = "count"
                let newRelation = self.relation.count()
                let newArrayProperty = newRelation.arrayProperty(idAttr: idAttr, orderAttr: idAttr)
                return Output(relation: newRelation, arrayProperty: newArrayProperty, orderedAttrs: [idAttr])
            }
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
