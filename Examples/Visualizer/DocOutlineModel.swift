//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelational
import PLRelationalBinding
import PLBindableControls

enum DocOutlineSectionID: Int64 { case
    relations
    
    init?(_ value: RelationValue) {
        self.init(rawValue: value.get()!)!
    }
    
    var sectionedTreeSectionID: SectionedTreeSectionID {
        return SectionedTreeSectionID(rawID: rawValue)
    }
}

enum DocOutlineChildren { case
    array(ArrayProperty<RowArrayElement>),
    tree(TreeProperty<RowTreeNode>)
    
    func start() {
        switch self {
        case .array(let prop):
            prop.start()
        case .tree(let prop):
            prop.start()
        }
    }
}

class DocOutlineSection {
    let id: DocOutlineSectionID
    let cellText: TextProperty?
    let children: DocOutlineChildren?
    
    init(id: DocOutlineSectionID, cellText: TextProperty?, children: DocOutlineChildren?) {
        self.id = id
        self.cellText = cellText
        self.children = children
    }
    
    func start() {
        children?.start()
    }
    
    func outlineViewRowCount() -> Int {
        switch id {
        case .relations:
            // We explode the top-level nodes of the pages tree property so that they appear at the top level
            // of our custom tree view
            return outlineViewChildCount()
        }
    }
    
    func outlineViewChildCount() -> Int {
        if let children = children {
            switch children {
            case .array(let prop):
                return prop.elements.count
            case .tree(let prop):
                return prop.root.children.count
            }
        } else {
            return 0
        }
    }
    
    func child(atIndex index: Int) -> Any {
        switch children! {
        case .array(let prop):
            return prop.elements[index]
        case .tree(let prop):
            return prop.root.children[index]
        }
    }
    
    func descendant(forID id: RelationValue) -> Any? {
        switch children! {
        case .array(let prop):
            return prop.elementForID(id)
        case .tree(let prop):
            return prop.nodeForID(id)
        }
    }
    
    var childrenArray: ArrayProperty<RowArrayElement>? {
        switch children! {
        case .array(let prop):
            return prop
        default:
            return nil
        }
    }
    
    var childrenTree: TreeProperty<RowTreeNode>? {
        switch children! {
        case .tree(let prop):
            return prop
        default:
            return nil
        }
    }
}

extension DocOutlineSection: CustomStringConvertible {
    public var description: String {
        switch id {
        case .relations: return "DocOutlineSection(Relations)"
        }
    }
}

enum DocOutlinePath { case
    // For now we only have a single section, but maybe later we'll have more
    relation(docItemID: DocItemID, objectID: ObjectID, type: ItemType)
    
    var objectID: ObjectID {
        switch self {
        case let .relation(_, oid, _):
            return oid
        }
    }
    
    var type: ItemType {
        switch self {
        case let .relation(_, _, t):
            return t
        }
    }
}

extension DocOutlinePath: Equatable {}
func ==(a: DocOutlinePath, b: DocOutlinePath) -> Bool {
    switch (a, b) {
    case let (.relation(adid, aoid, _), .relation(bdid, boid, _)): return adid == bdid && aoid == boid
    }
}

extension DocOutlinePath: Hashable {
    func hash(into hasher: inout Hasher) {
        switch self {
        case let .relation(did, oid, _):
            hasher.combine(did)
            hasher.combine(oid)
        }
    }
}

class DocOutlineModel: SectionedTreeViewModel {
    
    typealias Path = DocOutlinePath
    
    // XXX: Two-way dependency here, need to break this
    private let docModel: DocModel
    private let db: DocDatabase
    private var tagPages: [ObjectID: ArrayProperty<RowArrayElement>] = [:]
    private var observerRemovals: [ObserverRemoval] = []
    
    let selection: AsyncReadWriteProperty<Set<DocOutlinePath>>
    var selectionExclusiveMode: Bool = false
    
    weak var delegate: SectionedTreeViewModelDelegate?
    
    let relationsSection: DocOutlineSection
    private let sections: [DocOutlineSection]
    
    init(docModel: DocModel, db: DocDatabase, docItems: TreeProperty<RowTreeNode>) {
        self.docModel = docModel
        self.db = db
        
        self.selection = docModel.activeTabSelectedDocOutlinePaths
        
        self.relationsSection = DocOutlineSection(id: .relations, cellText: nil, children: .tree(docItems))
        self.sections = [relationsSection]
        
        let docItemsRemoval = docItems.signal.observeValueChanging{ changes, _ in
            self.handleDocItemsTreeChanges(changes)
        }
        observerRemovals.append(docItemsRemoval)
    }
    
    deinit {
        observerRemovals.forEach{ $0() }
    }
    
    private func outlineViewTopLevelRowCount() -> Int {
        var count = 0
        for section in sections {
            count += section.outlineViewRowCount()
        }
        return count
    }
    
    func start() {
        selection.start()
        relationsSection.start()
    }
    
    func itemForPath(_ path: DocOutlinePath) -> Any? {
        switch path {
        case let .relation(docItemID, _, _):
            return relationsSection.descendant(forID: docItemID.relationValue)
        }
    }
    
    func pathForItem(_ item: Any?) -> DocOutlinePath? {
        switch item {
        case is DocOutlineSection:
            // TODO: For now, we ignore the case where a section cell is selected
            return nil
            
        case let element as RowCollectionElement:
            let type = ItemType(element.data)!
            switch sectionIDForElement(element) {
            case .some(.relations):
                let docItemID = DocItemID(element.id)
                let objectID = ObjectID(element.data[DB.Object.ID.a])
                return DocOutlinePath.relation(docItemID: docItemID, objectID: objectID, type: type)
            default:
                return nil
            }
            
        default:
            return nil
        }
    }
    
    func childCountForItem(_ item: Any?) -> Int {
        switch item {
        case nil:
            return outlineViewTopLevelRowCount()
            
        case let section as DocOutlineSection:
            return section.outlineViewChildCount()
            
        case let node as RowTreeNode:
            return node.children.count
            
        case is RowArrayElement:
            return 0
            
        default:
            fatalError("Unexpected item type")
        }
    }
    
    func child(index: Int, ofItem item: Any?) -> Any {
        switch item {
        case nil:
            // This is a top-level node in the relations section
            return relationsSection.child(atIndex: index)
            
        case let section as DocOutlineSection:
            return section.child(atIndex: index)
            
        case let node as RowTreeNode:
            return node.children[index]
            
        case is RowArrayElement:
            fatalError("Not a parent")
            
        default:
            fatalError("Unexpected item type")
        }
    }
    
    func isItemExpandable(_ item: Any) -> Bool {
        switch item {
        case let section as DocOutlineSection:
            return section.outlineViewChildCount() > 0
            
        case let node as RowTreeNode:
            return node.children.count > 0
            
        case is RowArrayElement:
            return false
            
        default:
            fatalError("Unexpected item type")
        }
    }
    
    func isItemSelectable(_ item: Any) -> Bool {
        switch item {
        case is DocOutlineSection:
            return true
            
        case let element as RowCollectionElement:
            let itemType = ItemType(element.data)!
            switch itemType {
            case .section:
                return false
            default:
                return true
            }
            
        default:
            fatalError("Unexpected item type")
        }
    }
    
    func isOutlineViewGroupStyle(_ item: Any) -> Bool {
        switch item {
        case is DocOutlineSection:
            return false
            
        case let element as RowCollectionElement:
            let itemType = ItemType(element.data)!
            return itemType == .section
            
        default:
            fatalError("Unexpected item type")
        }
    }
    
    func cellIdentifier(_ item: Any) -> String {
        switch item {
        case let section as DocOutlineSection:
            switch section.id {
            case .relations:
                return "RelationCell"
            }
            
        case let element as RowCollectionElement:
            let itemType = ItemType(element.data)!
            if itemType == .section {
                return "SectionCell"
            } else {
                return "PageCell"
            }
            
        default:
            fatalError("Unexpected item type")
        }
    }
    
    func cellText(_ item: Any) -> TextProperty? {
        switch item {
        case let section as DocOutlineSection:
            return section.cellText
            
        case let element as RowCollectionElement:
            let row = element.data
            let objectID: RelationValue
            switch sectionIDForElement(element) {
            case .some(.relations):
                objectID = row[DB.DocItem.ObjectID.a]
            default:
                fatalError("Unexpected section")
            }
            let initialName: String? = row[DB.Object.Name.a].get()
            let property = db.objectNameReadWriteProperty(objectID: ObjectID(objectID), initialValue: initialName)
            return .asyncReadWriteOpt(property)
            
        default:
            fatalError("Unexpected item type")
        }
    }
    
    func cellImage(_ item: Any) -> ReadableProperty<Image>? {
        switch item {
        case is DocOutlineSection:
            // TODO: Return appropriate icon
            return nil
            
        case is RowCollectionElement:
            // TODO: Return appropriate icon
            return nil
            
        default:
            fatalError("Unexpected item type")
        }
    }
    
    func contextMenu(forItem item: Any) -> ContextMenu? {
        return nil
    }
    
    func pasteboardPlistToMoveItem(_ item: Any) -> Any? {
        return nil
    }
    
    func isDropAllowed(plist: Any, proposedItem: Any?, proposedChildIndex proposedIndex: Int) -> Bool {
        return false
    }
    
    func acceptDrop(plist: Any, item: Any?, childIndex: Int) -> Bool {
        return false
    }
    
    func movePageItem(srcPath: TreePath<RowTreeNode>, dstPath: TreePath<RowTreeNode>) {
        let (nodeID, dstParentID, order) = relationsSection.childrenTree!.orderForMove(srcPath: srcPath, dstPath: dstPath)
        // TODO: s/Item/type.name/
        db.performUndoableAction("Move Item", {
            self.db.docItems.asyncUpdate(DB.DocItem.ID.a *== nodeID, newValues: [
                DB.DocItem.Parent.a: dstParentID ?? .null,
                DB.DocItem.Order.a: RelationValue(order)
            ])
        })
    }
    
    private func sectionIDForElement(_ element: RowCollectionElement) -> DocOutlineSectionID? {
        return Box<DocOutlineSectionID>.open(element.tag)
    }
    
    private func handleArrayChanges(_ sectionID: DocOutlineSectionID, sectionPath: SectionedTreePath?,
                                    _ changes: [ArrayChange<RowArrayElement>], _ transform: (Int) -> SectionedTreePath?)
    {
        guard let delegate = delegate else { return }
        
        let sectionedTreeChanges: [SectionedTreeChange] = changes.compactMap{
            switch $0 {
            case .initial:
                return .initial(sectionID: sectionID.sectionedTreeSectionID, path: sectionPath)
            case .insert(let index):
                return transform(index).map{.insert($0)}
            case .delete(let index):
                return transform(index).map{.delete($0)}
            case .update:
                // TODO: For now we will ignore updates and assume that the cell contents will
                // be updated individually in response to the change.  We should make this
                // configurable to allow for optionally calling reloadItem() to refresh the
                // entire cell on any non-trivial update.
                return nil
            case .move(let srcIndex, let dstIndex):
                if let src = transform(srcIndex), let dst = transform(dstIndex) {
                    return .move(src: src, dst: dst)
                } else {
                    return nil
                }
            }
        }
        
        if sectionedTreeChanges.count > 0 {
            delegate.sectionedTreeViewModelTreeChanged(sectionedTreeChanges)
        }
    }
    
    private func handleTreeChanges(_ sectionID: DocOutlineSectionID, sectionPath: SectionedTreePath?,
                                   _ changes: [TreeChange<RowTreeNode>], _ transform: (TreePath<RowTreeNode>) -> SectionedTreePath)
    {
        guard let delegate = delegate else { return }
        
        let sectionedTreeChanges: [SectionedTreeChange] = changes.compactMap{
            switch $0 {
            case .initial:
                return .initial(sectionID: sectionID.sectionedTreeSectionID, path: sectionPath)
            case .insert(let path):
                return .insert(transform(path))
            case .delete(let path):
                return .delete(transform(path))
            case .update:
                // TODO: For now we will ignore updates and assume that the cell contents will
                // be updated individually in response to the change.  We should make this
                // configurable to allow for optionally calling reloadItem() to refresh the
                // entire cell on any non-trivial update.
                return nil
            case .move(let srcPath, let dstPath):
                return .move(src: transform(srcPath), dst: transform(dstPath))
            }
        }
        
        if sectionedTreeChanges.count > 0 {
            delegate.sectionedTreeViewModelTreeChanged(sectionedTreeChanges)
        }
    }
    
    private func handleDocItemsTreeChanges(_ changes: [TreeChange<RowTreeNode>]) {
        handleTreeChanges(.relations, sectionPath: nil, changes, { path in
            return SectionedTreePath(parent: path.parent, index: path.index)
        })
    }
}
