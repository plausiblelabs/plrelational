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
    
    // XXX: This is a unique identifier that allows for determining whether an async query is still valid
    // i.e., whether the content should be set
    private var currentContentLoadID: UUID?

    private var observerRemovals: [ObserverRemoval] = []
    
    init(frame: NSRect, model: DocModel) {
        self.docModel = model
        
        super.init(frame: frame)
        
        let activeItemRemoval = model.activeTabCurrentHistoryItem.signal.observe{ historyItem, _ in
            if let historyItem = historyItem {
                let docOutlinePath = historyItem.outlinePath
                switch docOutlinePath.type {
                case .storedRelation:
                    self.setStoredRelationContent(docOutlinePath)
//                case .sharedRelation, .privateRelation:
//                    break
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
    
    private func setStoredRelationContent(_ docOutlinePath: DocOutlinePath) {
        prepareForNewContent()

        // Add the content view
        let chainView = BackgroundView(frame: self.bounds)
        chainView.backgroundColor = NSColor(white: 0.98, alpha: 1.0)
        addSubview(chainView)
        self.contentView = chainView
        
        // Load the relation model asynchronously
        let contentLoadID = UUID()
        currentContentLoadID = contentLoadID
        let contentRelation = docModel.storedRelationModel(objectID: docOutlinePath.objectID)
        contentRelation.asyncAllRows{ result in
            // Only set the loaded data if our content load ID matches
            if self.currentContentLoadID != contentLoadID {
                return
            }
            // TODO: Show error message if any step fails here
            guard let rows = result.ok else { return }
            guard let plistBlob = contentRelation.oneBlobOrNil(AnyIterator(rows.makeIterator())) else { return }
            guard let model = StoredRelationModel.fromPlistData(Data(bytes: plistBlob)) else { return }
            self.addRelationTables(fromModel: model, toView: chainView)
        }
    }
    
    private func addRelationTables(fromModel model: StoredRelationModel, toView view: NSView) {
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
            scrollView.borderType = .bezelBorder
            let tableView = TableView(model: model, tableView: nsTableView)
            tableView.animateChanges = true
            view.addSubview(scrollView)
        }

//        addTableView(
//            x: 20, y: 20,
//            relation: employees,
//            idAttr: "emp_id",
//            orderedAttrs: ["emp_id", "emp_name", "dept_name"])
//        addTableView(
//            x: 400, y: 20,
//            relation: departments,
//            idAttr: "dept_name",
//            orderedAttrs: ["dept_name", "manager_id"])
//        addTableView(
//            x: 20, y: 260,
//            relation: joined,
//            idAttr: "emp_id",
//            orderedAttrs: ["emp_id", "emp_name", "dept_name", "manager_id"])
        
        addTableView(
            x: 20, y: 20,
            relation: model.toRelation(),
            idAttr: model.idAttr,
            orderedAttrs: model.attributes)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        observerRemovals.forEach{ $0() }
    }
}
