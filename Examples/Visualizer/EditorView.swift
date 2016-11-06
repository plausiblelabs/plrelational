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
    
//    private var relTableView1: RelationTableView!
//    private var relTableView2: RelationTableView!
//    private var relTableView3: RelationTableView!
    
    init(frame: NSRect, model: DocModel) {
        self.docModel = model
        
        super.init(frame: frame)
        
//        let employees = MakeRelation(
//            ["emp_id", "emp_name", "dept_name"],
//            [1, "Alice", "Sales"],
//            [2, "Bob", "Finance"],
//            [3, "Carlos", "Production"],
//            [4, "Donald", "Production"])
//        
//        let departments = MakeRelation(
//            ["dept_name", "manager_id"],
//            ["Sales", 1],
//            ["Production", 3])
//        
//        let joined = employees.leftOuterJoin(departments)
//        
//        func tableView(relation: Relation,
//                       idAttr: Attribute, orderedAttrs: [Attribute],
//                       underlying: NSTableView) -> RelationTableView
//        {
//            let columns = orderedAttrs.map{ RelationTableColumnModel(identifier: $0, title: $0.name) }
//            let data = relation.arrayProperty(idAttr: idAttr, orderAttr: idAttr)
//            let model = TableViewModel(
//                columns: columns,
//                data: data,
//                cellText: { attribute, row in
//                    let rowID = row[idAttr]
//                    // TODO: For now we will convert non-string values to a string for display in
//                    // the cell, but eventually we should have native support for these
//                    let initialStringValue = row[attribute].description
//                    let textProperty = relation
//                        .select(idAttr *== rowID)
//                        .project(attribute)
//                        .asyncProperty(initialValue: initialStringValue, { $0.oneValueOrNil($1)?.description ?? "" })
//                    return .asyncReadOnly(textProperty)
//            }
//            )
//            let view = TableView(model: model, tableView: underlying)
//            view.animateChanges = true
//            return view
//        }
//        
//        relTableView1 = tableView(
//            relation: employees,
//            idAttr: "emp_id",
//            orderedAttrs: ["emp_id", "emp_name", "dept_name"],
//            underlying: tableView1)
//        relTableView2 = tableView(
//            relation: departments,
//            idAttr: "dept_name",
//            orderedAttrs: ["dept_name", "manager_id"],
//            underlying: tableView2)
//        relTableView3 = tableView(
//            relation: joined,
//            idAttr: "emp_id",
//            orderedAttrs: ["emp_id", "emp_name", "dept_name", "manager_id"],
//            underlying: tableView3)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        observerRemovals.forEach{ $0() }
    }
}
