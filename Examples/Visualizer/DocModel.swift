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
    
    /// Stores data that is referenced by a RelationModel.
    class ReferenceData {
        var models: [RelationValue: RelationModel] = [:]
    }
    
    /// Asynchronously loads the RelationViewModel for the given object.
    // TODO: Allow for cancellation
    private func loadRelationViewModel(objectID: ObjectID, completion: @escaping (RelationViewModel?) -> Void) {
        
        func queriesForIDs(_ relation: RelationObject, _ attr: Attribute, _ values: [RelationValue]) -> [RecursiveQuery] {
            return values.map{ RecursiveQuery(relation: relation, attr: attr, value: $0) }
        }

        db.relationModelData.recursiveSelect(
            initialQueryAttr: DB.RelationModelData.ObjectID.a,
            initialQueryValue: objectID.relationValue,
            initialValue: ReferenceData(),
            rowCallback: { (relation, row, accum) -> Result<(ReferenceData, [RecursiveQuery]), RelationError> in
                guard let plistBlob: [UInt8] = row[DB.RelationModelData.Plist.a].get() else {
                    return .Err(DocModelError(message: "Invalid plist data"))
                }
                guard let model = RelationModel.fromPlistData(Data(bytes: plistBlob)) else {
                    return .Err(DocModelError(message: "Failed to decode RelationModel plist data"))
                }
                
                // Save the model that was loaded
                let rowID = row[DB.RelationModelData.ObjectID.a]
                accum.models[rowID] = model

                // Determine whether we need to make any further queries
                let queries: [RecursiveQuery]
                switch model {
                case .stored:
                    // There's just one relation, and we already loaded it
                    queries = []
                case .shared(let sharedRelationModel):
                    // Determine all relations referenced by this model
                    let objectIDsToLoad = sharedRelationModel.referencedObjectIDs().map{ $0.relationValue }
                    queries = queriesForIDs(self.db.relationModelData, DB.RelationModelData.ObjectID.a, objectIDsToLoad)
                }
                
                let result: (ReferenceData, [RecursiveQuery]) = (accum, queries)
                return .Ok(result)
            },
            filterCallback: { accum, queries in
                // Filter out queries for those cases where we've already fetched the model
                var validQueries: Set<RecursiveQuery> = []
                for query in queries {
                    let rowID = query.value
                    if accum.models[rowID] == nil {
                        validQueries.insert(query)
                    }
                }
                return validQueries
            },
            completionCallback: { result in
                // Convert RelationModels -> RelationViewModel
                if let referenceData = result.ok {
                    // Convert RelationValue identifier keys -> ObjectID
                    let modelDict = Dictionary(referenceData.models.map{ (key, value) in (ObjectID(key), value) })
                    let viewModel = RelationViewModel(rootID: objectID, models: modelDict)
                    completion(viewModel)
                } else {
                    // TODO: Return error result
                    completion(nil)
                }
            }
        )
    }
    
    /// The RelationViewModel for the active tab's selected outline item.
    lazy var selectedObjectRelationViewModel: AsyncReadableProperty<AsyncState<RelationViewModel?>> = {
        // XXX: This is a unique identifier that allows for determining whether an async query is still valid
        // i.e., whether the loaded content should be delivered or discarded
        var currentContentLoadID: UUID?

        // Create a new signal that will deliver the AsyncState changes
        var latestAsyncState: AsyncState<RelationViewModel?> = .idle(nil)
        let signal = PipeSignal<AsyncState<RelationViewModel?>>()

        func loadViewModel(_ objectID: ObjectID) {
            let contentLoadID = UUID()
            currentContentLoadID = contentLoadID
            
            self.loadRelationViewModel(objectID: objectID, completion: { model in
                // Only deliver the loaded data if our content load ID matches
                if currentContentLoadID != contentLoadID { return }
                // Only deliver if we are in a loading state
                if case .idle = latestAsyncState { return }
                // Only deliver if model was successfully loaded
                guard let model = model else { return }
                
                signal.notifyValueChanging(.idle(model))
            })
        }
        
        // Observe the signal for the currently selected object.  When the selected object changes,
        // we deliver a `loading` state change prior to initiating the async query, and then deliver
        // the fully realized TextObjectData upon completion.
        var changeCount = 0
        let removal = self.activeTabCurrentHistoryItem.signal.observe{ event in
            switch event {
            case .beginPossibleAsyncChange:
                changeCount += 1
                signal.notifyBeginPossibleAsyncChange()
                
            case let .valueChanging(change, _):
                let asyncState: AsyncState<RelationViewModel?>
                if let historyItem = change {
                    let docOutlinePath = historyItem.outlinePath
                    switch docOutlinePath.type {
                    case .storedRelation, .sharedRelation:
                        // Asynchronously load the relation model data
                        loadViewModel(docOutlinePath.objectID)
                        asyncState = .loading
                    default:
                        // Selected item is not a relation object
                        asyncState = .idle(nil)
                    }
                } else {
                    // No item is selected
                    asyncState = .idle(nil)
                }
                latestAsyncState = asyncState
                signal.notifyValueChanging(asyncState)
                
            case .endPossibleAsyncChange:
                changeCount -= 1
                signal.notifyEndPossibleAsyncChange()
            }
        }
        self.observerRemovals.append(removal)
        
        // Deliver the latest value when an observer is attached
        signal.onObserve = { observer in
            for _ in 0..<changeCount {
                // If activeTabCurrentHistoryItem.signal is in an asynchronous change (delivered BeginPossibleAsync
                // before this observer was attached), we need to give this new observer the corresponding
                // number of BeginPossibleAsync notifications so that it is correctly balanced when the
                // EndPossibleAsync notification(s) come in later
                observer.notifyBeginPossibleAsyncChange()
            }
            observer.notifyValueChanging(latestAsyncState)
        }
        
        return signal.property()
    }()
}

// XXX: Placeholder error type
private struct DocModelError: Error {
    let message: String
}
