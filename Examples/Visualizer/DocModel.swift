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
        
        // XXX: Eagerly start some properties that are dependencies of other actions
        self.activeTabID.start()
    }
    
    /// The selected tab identifier.
    lazy var activeTabID: AsyncReadWriteProperty<RelationValue?> = {
        return self.db.undoableBidiProperty(
            action: "Change Tab",
            signal: self.db.selectedTab.signal{
                return $0.oneValueOrNil($1)
            },
            update: { id in
                let tabID = id.flatMap(TabID.fromNullable)
                self.db.setSelectedTab(tabID: tabID)
        }
        )
    }()

    /// The current history item for the active tab.
    lazy var activeTabCurrentHistoryItem: AsyncReadableProperty<HistoryItem?> = {
        return self.db.selectedTabCurrentHistoryItem
            .asyncProperty{
                $0.oneValueFromRow($1, { row in
                    return HistoryItem.fromRow(row)
                })
        }
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
                    if self.db.isBusy {
                        print("WARNING: Attempting to change doc outline selection while database is busy")
                        return
                    }
                    _ = self.selectDocOutlineItem(path: path)
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
}
