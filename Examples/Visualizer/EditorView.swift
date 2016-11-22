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
    let width: CGFloat
}

private typealias RelationTableView = TableView<RelationTableColumnModel, RowArrayElement>

private let startX: CGFloat = 20
private let startY: CGFloat = 60

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
        
        let currentViewModelRemoval = model.selectedObjectRelationViewModel.signal.observe{ asyncState, _ in
            switch asyncState {
            case .loading:
                // Clear view while new model is being loaded
                // TODO: Show progress indicator, maybe
                self.prepareForNewContent()
            case .idle(let viewModel):
                if let viewModel = viewModel {
                    // Display the tables for the loaded view model
                    self.setRelationContent(viewModel)
                } else {
                    // Nothing selected (or the model failed to load); clear the view
                    self.prepareForNewContent()
                }
            }
        }
        observerRemovals.append(currentViewModelRemoval)
        model.selectedObjectRelationViewModel.start()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        observerRemovals.forEach{ $0() }
    }
    
    private func prepareForNewContent() {
        // TODO: Commit changes for current selection
        contentView?.removeFromSuperview()
        tableViews.removeAll()
    }
    
    private func setRelationContent(_ viewModel: RelationViewModel) {
        prepareForNewContent()

        // Add the content view
        let chainView = BackgroundView(frame: self.bounds)
        chainView.backgroundColor = NSColor(white: 0.98, alpha: 1.0)
        chainView.autoresizingMask = [.viewWidthSizable, .viewHeightSizable]
        addSubview(chainView)
        self.contentView = chainView
        
        // Display the tables
        guard let rootModel = viewModel.models[viewModel.rootID] else {
            // TODO: Show error message
            Swift.print("ERROR: No model data found for root")
            return
        }
        switch rootModel {
        case .stored(let storedModel):
            addStoredRelationTable(fromModel: storedModel, toView: chainView, x: startX, y: startY)
        case .shared(let sharedModel):
            addSharedRelationTables(fromModel: sharedModel, referencedRelationModels: viewModel.models, toView: chainView)
        }
    }

    private func addStoredRelationTable(fromModel model: StoredRelationModel,
                                        toView parent: NSView, x: CGFloat, y: CGFloat)
    {
        addTableView(
            to: parent,
            x: x, y: y,
            relation: model.toRelation(),
            idAttr: model.idAttr,
            orderedAttrs: model.attributes)
    }
    
    private func addSharedRelationTables(fromModel model: SharedRelationModel,
                                         referencedRelationModels: [ObjectID: RelationModel],
                                         toView parent: NSView)
    {
        // TODO: Move all accumulation logic to RelationViewModel
        struct Accum {
            let relation: Relation
            let idAttr: Attribute
            let orderedAttrs: [Attribute]
        }
        
        var x: CGFloat = startX
        var y: CGFloat = startY
        let padX: CGFloat = 40
        let padY: CGFloat = 40
        
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
    
    private func addTableView(to parent: NSView, x: CGFloat, y: CGFloat, relation: Relation,
                              idAttr: Attribute, orderedAttrs: [Attribute])
    {
        let columns = orderedAttrs.map{ RelationTableColumnModel(identifier: $0, title: $0.name, width: 80) }
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
                    .oneValue({ $0.description }, orDefault: "", initialValue: initialStringValue)
                    .property()
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
}
