//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import PLRelational
import PLRelationalBinding

class DocModel {
    
    private let db: DocDatabase
    
    /// The tree of doc outline items for the "relations" section.
    private let docItemsTree: TreeProperty<RowTreeNode>
    
    /// Keep the most recent pending selection path, which will be processed the next time the database is freed up.
    private var pendingSelectionPath: DocOutlinePath?
    
    private var observerRemovals: [ObserverRemoval] = []

    init(db: DocDatabase) {
        self.db = db
        
        // Prepare the doc outline tree property
        let objectsWithRenamedID = db.objects.renameAttributes([DB.Object.ID.a: DB.DocItem.ObjectID.a])
        let docObjects = db.docItems.join(objectsWithRenamedID)
        self.docItemsTree = docObjects.treeProperty(
            idAttr: DB.DocItem.ID.a,
            parentAttr: DB.DocItem.Parent.a,
            orderAttr: DB.DocItem.Order.a,
            tag: Box(DocOutlineSectionID.relations))
        
        // Observe the AsyncManager state and handle enqueued selection changes
        let stateObserverRemover = AsyncManager.currentInstance.addStateObserver({
            if $0 == .idle {
                if let path = self.pendingSelectionPath {
                    // Update the database with the enqueued selection change
                    self.pendingSelectionPath = nil
                    _ = self.selectDocOutlineItem(path: path)
                } else {
                    // No pending selection change, so exit exclusive mode
                    self.docOutlineModel.selectionExclusiveMode = false
                }
            }
        })
        observerRemovals.append(stateObserverRemover)

        // XXX: Eagerly start some properties that are dependencies of other actions
        self.activeTabID.start()
    }
    
    deinit {
        observerRemovals.forEach{ $0() }
    }

    lazy var leftSidebarVisible: MutableValueProperty<Bool> = {
        return mutableValueProperty(true)
    }()
    
    lazy var rightSidebarVisible: MutableValueProperty<Bool> = {
        return mutableValueProperty(true)
    }()
    
    lazy var docOutlineModel: DocOutlineModel = {
        return DocOutlineModel(docModel: self, db: self.db, docItems: self.docItemsTree)
    }()
    
    lazy var sidebarModel: SidebarModel = {
        return SidebarModel(
            db: self.db,
            selectedObjects: self.db.selectedTabCurrentObject
        )
    }()
    
    /// The selected tab identifier.
    lazy var activeTabID: AsyncReadWriteProperty<RelationValue?> = {
        return self.db.undoableBidiProperty(
            action: "Change Tab",
            signal: self.db.selectedTab.oneRelationValueOrNil(),
            update: { id in
                let tabID = id.flatMap(TabID.fromNullable)
                self.db.setSelectedTab(tabID: tabID)
            }
        )
    }()

    /// The current history item for the active tab.
    lazy var activeTabCurrentHistoryItem: AsyncReadableProperty<HistoryItem?> = {
        return self.db.selectedTabCurrentHistoryItem
            .valueFromOneRow{ HistoryItem.fromRow($0) }
            .property()
    }()
    
    /// The path(s) for the active tab's selected outline item.  Currently we assume either zero
    /// or one selected item, but the property has a value type of Set<DocOutlinePath> for compatibility
    /// with SectionedTreeView and to allow for the multiple selection case in the future.
    lazy var activeTabSelectedDocOutlinePaths: AsyncReadWriteProperty<Set<DocOutlinePath>> = {
        // TODO: Do we need to explicitly start this underlying property here?
        self.activeTabCurrentHistoryItem.start()
        
        return self.db.undoableBidiProperty(
            action: "Change Selection",
            signal: self.activeTabCurrentHistoryItem.signal.map{ item in
                if let item = item {
                    return [item.outlinePath]
                } else {
                    return []
                }
            },
            update: { paths in
                if let path = paths.first {
                    // XXX: Put the outline selection model into a sort of "exclusive mode" while the user
                    // is changing the selection.  This helps prevent updating the outline view's selection
                    // when the database's selection state is changing (possibly with some latency).  The
                    // downside is that we run the risk of missing some non-user-initiated update to the
                    // database's selection state while we are in exclusive mode.
                    self.docOutlineModel.selectionExclusiveMode = true
                    
                    if self.db.isBusy {
                        // Queue up this path and update the database the next time it is idle
                        self.pendingSelectionPath = path
                    } else {
                        // Update the database immediately
                        _ = self.selectDocOutlineItem(path: path)
                    }
                }
            }
        )
    }()
    
    /// Selects the outline item at the given path, adding a new history item for the active tab.
    func selectDocOutlineItem(path: DocOutlinePath) -> HistoryItemID? {
        guard let currentTabID = activeTabID.value ?? nil else {
            print("WARNING: Attempting to change doc outline selection while current tab is unknown")
            return nil
        }
        let currentPosition = activeTabCurrentHistoryItem.value??.position
        return db.selectDocOutlineItem(tabID: TabID(currentTabID), path: path, currentPosition: currentPosition)
    }
    
    /// Returns a Relation that contains the relation model for the given object.
    private func relationModelPlistData(objectID: ObjectID) -> Relation {
        return db.relationModelData
            .select(DB.RelationModelData.ObjectID.a *== objectID.relationValue)
            .project(DB.RelationModelData.Plist.a)
    }
    
    /// Asynchronously loads the RelationViewModel for the given object.
    // TODO: Allow for cancellation
    private func loadRelationViewModel(objectID: ObjectID, completion: @escaping (RelationViewModel?) -> Void) {
        db.relationModelData.recursiveSelect(
            idAttr: DB.RelationModelData.ObjectID.a,
            initialID: objectID.relationValue,
            rowCallback: { row -> Result<(RelationModel, [RelationValue]), RelationError> in
                guard let plistBlob: [UInt8] = row[DB.RelationModelData.Plist.a].get() else {
                    return .Err(DocModelError(message: "Invalid plist data"))
                }
                if let model = RelationModel.fromPlistData(Data(bytes: plistBlob)) {
                    let objectIDsToLoad: [RelationValue]
                    switch model {
                    case .stored:
                        // There's just one relation, and we already loaded it
                        objectIDsToLoad = []
                    case .shared(let sharedRelationModel):
                        // Determine all relations referenced by this model
                        objectIDsToLoad = sharedRelationModel.referencedObjectIDs().map{ $0.relationValue }
                    }
                    let result: (RelationModel, [RelationValue]) = (model, objectIDsToLoad)
                    return .Ok(result)
                } else {
                    return .Err(DocModelError(message: "Failed to decode RelationModel plist data"))
                }
            },
            completionCallback: { result in
                // TODO: Convert RelationModels -> RelationViewModel
                completion(nil)
            }
        )
    }
    
    /// The RelationViewModel for the active tab's selected outline item.
    lazy var selectedRelationViewModel: AsyncReadableProperty<AsyncState<RelationViewModel?>> = {
        // TODO: Do we need to explicitly start this underlying property here?
        self.activeTabCurrentHistoryItem.start()

        // XXX: This is a unique identifier that allows for determining whether an async query is still valid
        // i.e., whether the content should be set
        var currentContentLoadID: UUID?
        
//        let contentLoadID = UUID()
//        currentContentLoadID = contentLoadID
//        let contentRelation = docModel.relationModelPlistData(objectID: docOutlinePath.objectID)
//        contentRelation.asyncAllRows(
//            postprocessor: { rows -> RelationModel? in
//                // TODO: Show error message if any step fails here
//                guard let plistBlob = contentRelation.extractOneBlobOrNil(from: AnyIterator(rows.makeIterator())) else { return nil }
//                return RelationModel.fromPlistData(Data(bytes: plistBlob))
//            },
//            completion: { result in
//                // Only set the loaded data if our content load ID matches
//                if self.currentContentLoadID != contentLoadID {
//                    return
//                }
//                guard let model = result.ok ?? nil else { return }
//                self.addRelationTables(fromModel: model, toView: chainView)
//            }
//        )
        
        return self.activeTabCurrentHistoryItem.signal
            .map{ historyItem in
                if let historyItem = historyItem {
                    let docOutlinePath = historyItem.outlinePath
                    switch docOutlinePath.type {
                    case .storedRelation, .sharedRelation:
                        // Asynchronously load the relation model data
                        // TODO
                        return AsyncState.loading
                    default:
                        // Selected item is not a relation object
                        return AsyncState.idle(nil)
                    }
                } else {
                    // No item is selected
                    return AsyncState.idle(nil)
                }
            }
            .property()
    }()
}

// XXX: Placeholder error type
public struct DocModelError: Error {
    let message: String
}
