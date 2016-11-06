//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelationalBinding
import PLBindableControls
import PLRelational

private struct RelationTableColumnModel: TableColumnModel {
    typealias ID = Attribute
    
    let identifier: Attribute
    var identifierString: String {
        return identifier.name
    }
    let title: String
}

private typealias RelationTableView = TableView<RelationTableColumnModel, RowArrayElement>

class EditorView: BackgroundView {
    
    private let docModel: DocModel
    private var contentView: NSView?
    
    private var observerRemovals: [ObserverRemoval] = []
    
    init(frame: NSRect, model: DocModel) {
        self.docModel = model
        
        super.init(frame: frame)
        
        let activeItemRemoval = model.activeTabCurrentHistoryItem.signal.observe{ historyItem, _ in
            if let historyItem = historyItem {
                let docOutlinePath = historyItem.outlinePath
                switch docOutlinePath.type {
                case .storedRelation, .sharedRelation, .privateRelation:
                    self.setRelationContent(docOutlinePath)
                default:
                    self.contentView?.removeFromSuperview()
                }
            } else {
                self.contentView?.removeFromSuperview()
            }
        }
        observerRemovals.append(activeItemRemoval)
        model.activeTabCurrentHistoryItem.start()
    }
    
    private func prepareForNewContent() {
        // TODO: Commit changes for current selection
        contentView?.removeFromSuperview()
    }
    
    func setRelationContent(_ docOutlinePath: DocOutlinePath) {
        prepareForNewContent()

        let chainView = BackgroundView(frame: self.bounds)
        
        let employees = MakeRelation(
            ["emp_id", "emp_name", "dept_name"],
            [1, "Alice", "Sales"],
            [2, "Bob", "Finance"],
            [3, "Carlos", "Production"],
            [4, "Donald", "Production"])
        
        let departments = MakeRelation(
            ["dept_name", "manager_id"],
            ["Sales", 1],
            ["Production", 3])
        
        let joined = employees.leftOuterJoin(departments)

        func addTableView(x: CGFloat, y: CGFloat, relation: Relation,
                          idAttr: Attribute, orderedAttrs: [Attribute])
        {
            let columns = orderedAttrs.map{ RelationTableColumnModel(identifier: $0, title: $0.name) }
            let data = relation.arrayProperty(idAttr: idAttr, orderAttr: idAttr)
            let model = TableViewModel(
                columns: columns,
                data: data,
                cellText: { attribute, row in
                    let rowID = row[idAttr]
                    // TODO: For now we will convert non-string values to a string for display in
                    // the cell, but eventually we should have native support for these
                    let initialStringValue = row[attribute].description
                    let textProperty = relation
                        .select(idAttr *== rowID)
                        .project(attribute)
                        .asyncProperty(initialValue: initialStringValue, { $0.oneValueOrNil($1)?.description ?? "" })
                    return .asyncReadOnly(textProperty)
                }
            )

            let scrollView = NSScrollView(frame: NSMakeRect(x, y, 340, 200))
            let nsTableView = NSTableView(frame: scrollView.bounds)
            nsTableView.allowsColumnResizing = true
            nsTableView.allowsColumnReordering = false
            scrollView.documentView = nsTableView
            scrollView.hasVerticalScroller = true
            let view = TableView(model: model, tableView: nsTableView)
            view.animateChanges = true
            chainView.addSubview(scrollView)
        }

        addTableView(
            x: 20, y: 20,
            relation: employees,
            idAttr: "emp_id",
            orderedAttrs: ["emp_id", "emp_name", "dept_name"])
        addTableView(
            x: 400, y: 20,
            relation: departments,
            idAttr: "dept_name",
            orderedAttrs: ["dept_name", "manager_id"])
        addTableView(
            x: 20, y: 260,
            relation: joined,
            idAttr: "emp_id",
            orderedAttrs: ["emp_id", "emp_name", "dept_name", "manager_id"])
        
        addSubview(chainView)
        self.contentView = chainView
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        observerRemovals.forEach{ $0() }
    }
}
