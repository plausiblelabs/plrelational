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
                case .storedRelation:
                    self.setStoredRelationContent(docOutlinePath)
                case .sharedRelation:
                    self.setSharedRelationContent(docOutlinePath)
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
    
    private func setStoredRelationContent(_ docOutlinePath: DocOutlinePath) {
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
            self.addStoredRelationTable(fromModel: model, toView: chainView, x: 20, y: 20)
        }
    }

    private func setSharedRelationContent(_ docOutlinePath: DocOutlinePath) {
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
        let contentRelation = docModel.sharedRelationModel(objectID: docOutlinePath.objectID)
        contentRelation.asyncAllRows{ result in
            // Only set the loaded data if our content load ID matches
            if self.currentContentLoadID != contentLoadID {
                return
            }
            // TODO: Show error message if any step fails here
            guard let rows = result.ok else { return }
            guard let plistBlob = contentRelation.oneBlobOrNil(AnyIterator(rows.makeIterator())) else { return }
            guard let model = SharedRelationModel.fromPlistData(Data(bytes: plistBlob)) else { return }
            self.addSharedRelationTables(fromModel: model, toView: chainView)
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
        // Determine which stored relations are referenced in this SharedRelationModel
        var referencedObjectIDs: Set<ObjectID> = []
        for element in model.elements {
            func processAtom(_ atom: SharedRelationAtom) {
                switch atom.source {
                case .previous:
                    break
                case .reference(let objectID):
                    referencedObjectIDs.insert(objectID)
                }
            }
            
            processAtom(element.atom)
            
            if let op = element.op {
                switch op {
                case .filter:
                    break
                case .combine(let binaryOp):
                    processAtom(binaryOp.atom)
                }
            }
        }

        // Asynchronously load the model for each of those stored relations
        let group = DispatchGroup()
        var storedRelationModels: [ObjectID: StoredRelationModel] = [:]
        for objectID in referencedObjectIDs {
            let contentRelation = docModel.storedRelationModel(objectID: objectID)
            group.enter()
            contentRelation.asyncAllRows{ result in
                group.leave()
                // TODO: Show error message if any step fails here
                guard let rows = result.ok else { return }
                guard let plistBlob = contentRelation.oneBlobOrNil(AnyIterator(rows.makeIterator())) else { return }
                guard let model = StoredRelationModel.fromPlistData(Data(bytes: plistBlob)) else { return }
                storedRelationModels[objectID] = model
            }
        }

        group.notify(queue: DispatchQueue.main, execute: {
            var x: CGFloat = 20
            var y: CGFloat = 20
            let padX: CGFloat = 20
            let padY: CGFloat = 20
            
            struct Accum {
                let relation: Relation
                let idAttr: Attribute
                let orderedAttrs: [Attribute]
            }
            
            var accumulated: Accum? = nil
            
            // Display the relation tables
            for element in model.elements {
                func addTableForAtom(_ atom: SharedRelationAtom, x: CGFloat, y: CGFloat) -> StoredRelationModel? {
                    switch atom.source {
                    case .previous:
                        return nil
                    case .reference(let objectID):
                        if let storedRelationModel = storedRelationModels[objectID] {
                            self.addStoredRelationTable(fromModel: storedRelationModel, toView: parent, x: x, y: y)
                            return storedRelationModel
                        } else {
                            // TODO: Error message?
                            return nil
                        }
                    }
                }
                
                // Add the left-side table
                let lhsModel = addTableForAtom(element.atom, x: x, y: y)
                if accumulated == nil {
                    guard let lhs = lhsModel else {
                        Swift.print("Missing relation for initial element in shared relation")
                        return
                    }
                    accumulated = Accum(
                        relation: lhs.toRelation(),
                        idAttr: lhs.idAttr,
                        orderedAttrs: lhs.attributes
                    )
                }

                if let op = element.op {
                    switch op {
                    case .filter(let unaryOp):
                        // Derive the relation that results from the filter operation
                        // TODO
                        break

                    case .combine(let binaryOp):
                        // Add a table to the right side that shows the relation being combined
                        let rhsModel = addTableForAtom(binaryOp.atom, x: x + tableW + padX, y: y)
                        
                        // Derive the relation that results from the combine operation
                        if let accum = accumulated, let rhs = rhsModel {
                            let lhsRelation = accum.relation
                            let rhsRelation = rhs.toRelation()
                            let combined: Relation
                            switch binaryOp {
                            case .join:
                                combined = lhsRelation.join(rhsRelation)
                            case .union:
                                combined = lhsRelation.union(rhsRelation)
                            }
                            // TODO: Determine idAttr for the combined relation (for now we'll take the
                            // one from the LHS always, but later when we handle projections, this may no
                            // longer be valid)
                            var orderedAttrs = accum.orderedAttrs
                            for attr in rhs.attributes {
                                if !orderedAttrs.contains(attr) {
                                    orderedAttrs.append(attr)
                                }
                            }
                            accumulated = Accum(
                                relation: combined,
                                idAttr: accum.idAttr,
                                orderedAttrs: orderedAttrs
                            )
                        } else {
                            Swift.print("Unable to combine relations from shared relation model, stopping early")
                            return
                        }
                    }
                    
                    // Add a table below the last one that displays the result of the operation
                    y += tableH + padY
                    if let accum = accumulated {
                        self.addTableView(
                            to: parent,
                            x: x, y: y,
                            relation: accum.relation,
                            idAttr: accum.idAttr,
                            orderedAttrs: accum.orderedAttrs)
                    } else {
                        Swift.print("No accumulated relation for shared relation model, stopping early")
                        return
                    }
                    
                } else {
                    // Stop early when we have no operation (this shouldn't be necessary if the model is well-formed,
                    // but just in case...)
                    Swift.print("Invalid shared relation model, stopping early")
                    return
                }
            }
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
