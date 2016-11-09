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

private let tableW: CGFloat = 340
private let tableH: CGFloat = 200

class EditorView: BackgroundView {
    
    private let docModel: DocModel
    private var contentView: NSView?
    private var tableViews: [RelationTableView] = []
    
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
                case .storedRelation, .sharedRelation:
                    self.setRelationContent(docOutlinePath)
                //case .privateRelation:
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
        tableViews.removeAll()
    }
    
    private func setRelationContent(_ docOutlinePath: DocOutlinePath) {
        prepareForNewContent()

        // Add the content view
        let chainView = BackgroundView(frame: self.bounds)
        chainView.backgroundColor = NSColor(white: 0.98, alpha: 1.0)
        chainView.autoresizingMask = [.viewWidthSizable, .viewHeightSizable]
        addSubview(chainView)
        self.contentView = chainView
        
        // Load the relation model asynchronously
        let contentLoadID = UUID()
        currentContentLoadID = contentLoadID
        let contentRelation = docModel.relationModelPlistData(objectID: docOutlinePath.objectID)
        contentRelation.asyncAllRows{ result in
            // Only set the loaded data if our content load ID matches
            if self.currentContentLoadID != contentLoadID {
                return
            }
            // TODO: Show error message if any step fails here
            guard let rows = result.ok else { return }
            guard let plistBlob = contentRelation.oneBlobOrNil(AnyIterator(rows.makeIterator())) else { return }
            guard let model = RelationModel.fromPlistData(Data(bytes: plistBlob)) else { return }
            self.addRelationTables(fromModel: model, toView: chainView)
        }
    }

    private func addRelationTables(fromModel model: RelationModel, toView parent: NSView) {
        switch model {
        case .stored(let storedModel):
            addStoredRelationTable(fromModel: storedModel, toView: parent, x: 20, y: 20)
        case .shared(let sharedModel):
            addSharedRelationTables(fromModel: sharedModel, toView: parent)
        }
    }

    private func addStoredRelationTable(fromModel model: StoredRelationModel, toView parent: NSView, x: CGFloat, y: CGFloat) {
        addTableView(
            to: parent,
            x: x, y: y,
            relation: model.toRelation(),
            idAttr: model.idAttr,
            orderedAttrs: model.attributes)
    }
    
    private func addSharedRelationTables(fromModel model: SharedRelationModel, toView parent: NSView) {
        // Determine which relations are referenced in this SharedRelationModel
        var referencedObjectIDs: Set<ObjectID> = []

        func processInput(_ input: SharedRelationInput) {
            referencedObjectIDs.insert(input.objectID)
        }
        
        processInput(model.input)
        for stage in model.stages {
            if let op = stage.op {
                switch op {
                case .filter:
                    break
                case .combine(let binaryOp):
                    processInput(binaryOp.rhs)
                }
            }
        }

        // Asynchronously load the model for each of those relations
        let group = DispatchGroup()
        var referencedRelationModels: [ObjectID: RelationModel] = [:]
        for objectID in referencedObjectIDs {
            let contentRelation = docModel.relationModelPlistData(objectID: objectID)
            group.enter()
            contentRelation.asyncAllRows{ result in
                defer {
                    group.leave()
                }
                // TODO: Show error message if any step fails here
                guard let rows = result.ok else { return }
                guard let plistBlob = contentRelation.oneBlobOrNil(AnyIterator(rows.makeIterator())) else { return }
                guard let model = RelationModel.fromPlistData(Data(bytes: plistBlob)) else { return }
                referencedRelationModels[objectID] = model
            }
        }
        
        struct Accum {
            let relation: Relation
            let idAttr: Attribute
            let orderedAttrs: [Attribute]
        }
        
        func displayTables() {
            var x: CGFloat = 20
            var y: CGFloat = 20
            let padX: CGFloat = 20
            let padY: CGFloat = 20
            
            func addTableForInput(_ input: SharedRelationInput, x: CGFloat, y: CGFloat) -> RelationModel {
                guard let relationModel = referencedRelationModels[input.objectID] else {
                    fatalError()
                }
                switch relationModel {
                case .stored(let model):
                    // TODO: Take projection into account
                    self.addStoredRelationTable(fromModel: model, toView: parent, x: x, y: y)
                case .shared:
                    fatalError("Not yet implemented")
                }
                return relationModel
            }

            // Add the root input
            let initialModel = addTableForInput(model.input, x: x, y: y)
            var accum: Accum
            switch initialModel {
            case .stored(let model):
                // TODO: Take initial projection into account
                accum = Accum(
                    relation: model.toRelation(),
                    idAttr: model.idAttr,
                    orderedAttrs: model.attributes
                )
            case .shared:
                fatalError("Not yet implemented")
            }

            for stage in model.stages {
                // TODO: Handle the case where there is a projection without an op
                guard let op = stage.op else { continue }
                
                switch op {
                case .filter(let unaryOp):
                    // Derive the relation that results from the filter operation
                    // TODO: Take projection into account
                    switch unaryOp {
                    case let .selectEq(attr, value):
                        accum = Accum(
                            relation: accum.relation.select(attr *== value),
                            idAttr: accum.idAttr,
                            orderedAttrs: accum.orderedAttrs
                        )
                    case .count:
                        accum = Accum(
                            relation: accum.relation.count(),
                            idAttr: "count",
                            orderedAttrs: ["count"]
                        )
                    }

                case .combine(let binaryOp):
                    // Add a table to the right side that shows the relation being combined
                    let rhsModel = addTableForInput(binaryOp.rhs, x: x + tableW + padX, y: y)
                    guard case .stored(let rhsStoredModel) = rhsModel else {
                        fatalError("Not yet implemented")
                    }
                    
                    // Derive the relation that results from the combine operation
                    let lhsRelation = accum.relation
                    let rhsRelation = rhsModel.toRelation()
                    let combined: Relation
                    switch binaryOp {
                    case .join:
                        combined = lhsRelation.join(rhsRelation)
                    case .union:
                        combined = lhsRelation.union(rhsRelation)
                    }
                    
                    if let projectedAttrs = stage.projection {
                        // XXX: For now, take the first projected attribute as the idAttr; need to
                        // figure out a way to make the ArrayProperty/TableView code less dependent
                        // on a unique identifier
                        accum = Accum(
                            relation: combined.project(Scheme(attributes: Set(projectedAttrs))),
                            idAttr: projectedAttrs.first!,
                            orderedAttrs: projectedAttrs
                        )
                    } else {
                        // TODO: Determine idAttr for the combined relation (for now we'll take the
                        // one from the LHS always, but later when we handle projections, this may no
                        // longer be valid)
                        var orderedAttrs = accum.orderedAttrs
                        for attr in rhsStoredModel.attributes {
                            if !orderedAttrs.contains(attr) {
                                orderedAttrs.append(attr)
                            }
                        }
                        accum = Accum(
                            relation: combined,
                            idAttr: accum.idAttr,
                            orderedAttrs: orderedAttrs
                        )
                    }
                }
                
                // Add a table below the last one that displays the result of the operation
                y += tableH + padY
                self.addTableView(
                    to: parent,
                    x: x, y: y,
                    relation: accum.relation,
                    idAttr: accum.idAttr,
                    orderedAttrs: accum.orderedAttrs)
            }
        }
        
        // When all model data is loaded, prepare the relation tables for display
        group.notify(queue: DispatchQueue.main, execute: {
            if referencedRelationModels.count != referencedObjectIDs.count {
                // Failed to load all the referenced models
                // TODO: We should be able to gracefully handle gaps in the data
                return
            }
            
            // Display the relation tables
            displayTables()
        })
    }
    
    private func addTableView(to parent: NSView, x: CGFloat, y: CGFloat, relation: Relation,
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
        
        let scrollView = NSScrollView(frame: NSMakeRect(x, y, tableW, tableH))
        let nsTableView = NSTableView(frame: scrollView.bounds)
        nsTableView.allowsColumnResizing = true
        nsTableView.allowsColumnReordering = false
        scrollView.documentView = nsTableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        let tableView = TableView(model: model, tableView: nsTableView)
        tableView.animateChanges = true
        parent.addSubview(scrollView)
        
        tableViews.append(tableView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        observerRemovals.forEach{ $0() }
    }
}
