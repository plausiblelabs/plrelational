//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import PLRelational
import PLRelationalBinding
import PLBindableControls

// TODO: Similar to what we did with `globalID`, we put all "type" constants that describe
// collections and objects into the same space, even though it would be more appropriate
// to have a `CollectionType` that is distinct from `ObjectType`.
enum ItemType: Int64 { case
    Group = 0,
    Collection = 1,
    Page = 2,
    Text = 3,
    Image = 4
    
    init?(_ value: RelationValue) {
        self.init(rawValue: value.get()!)!
    }
    
    init?(_ row: Row) {
        self.init(row["type"])
    }
    
    var name: String {
        switch self {
        case .Group: return "Group"
        case .Collection: return "Collection"
        case .Page: return "Page"
        case .Text: return "Text"
        case .Image: return "Image"
        }
    }
    
    var cellImageName: String {
        switch self {
        case .Group: return "group18"
        case .Collection: return "collection18"
        case .Page: return "page18"
        case .Text: return "label18"
        // TODO: Use a different icon for image, or better yet, make a thumbnail of
        // the associated image
        case .Image: return "label18"
        }
    }
    
    var isCollectionType: Bool {
        switch self {
        case .Group, .Collection, .Page:
            return true
        default:
            return false
        }
    }
    
    var isObjectType: Bool {
        return !isCollectionType
    }
}

class DocModel {
    
    private let db: TransactionalDatabase
    private let undoableDB: UndoableDatabase

    private var collections: TransactionalRelation
    private var objects: TransactionalRelation
    private var textObjects: TransactionalRelation
    private var imageObjects: TransactionalRelation
    private var selectedCollectionID: TransactionalRelation
    private var selectedInspectorItemIDs: TransactionalRelation
    
    private let inspectorItems: Relation
    private let selectedCollection: Relation
    private let selectedInspectorItems: Relation
    private let selectedItems: Relation

    private let docOutlineTree: TreeProperty<RowTreeNode>
    private let inspectorItemsTree: TreeProperty<RowTreeNode>
    
    // TODO: To simplify implementation of the relation that controls the inspector tree view,
    // we put identifiers for both the `collection` and `object` relations into the same set.
    // A potentially better/safer alternative would be to introduce compound primary key
    // support into RelationTreeProperty so that we can more easily merge data from different
    // source relations into a single relation.
    private var globalID: Int64 = 1
    
    private var removal: ObserverRemoval!
    
    init(undoManager: UndoManager) {

        func makeDB() -> (path: String, db: SQLiteDatabase) {
            let tmp = NSTemporaryDirectory() as NSString
            let dbname = "testing-\(NSUUID()).db"
            let path = tmp.stringByAppendingPathComponent(dbname)
            _ = try? NSFileManager.defaultManager().removeItemAtPath(path)
            
            let db = try! SQLiteDatabase(path)
            
            return (path, db)
        }
        
        // Prepare the stored relations
        let sqliteDB = makeDB().db
        let db = TransactionalDatabase(sqliteDB)
        func createRelation(name: String, _ scheme: Scheme) -> TransactionalRelation {
            let createResult = sqliteDB.createRelation(name, scheme: scheme)
            precondition(createResult.ok != nil)
            return db[name]
        }
        self.collections = createRelation("collection", ["id", "type", "name", "parent", "order"])
        self.objects = createRelation("object", ["id", "type", "name", "coll_id", "order"])
        self.textObjects = createRelation("text_object", ["id", "editable", "hint", "font"])
        self.imageObjects = createRelation("image_object", ["id", "editable"])
        self.selectedCollectionID = createRelation("selected_collection", ["coll_id"])
        self.selectedInspectorItemIDs = createRelation("selected_inspector_item", ["item_id"])

        // Prepare the higher level relations
        self.selectedCollection = selectedCollectionID
            .equijoin(collections, matching: ["coll_id": "id"])
            .project(["id", "type", "name"])
        
        // The `inspectorItems` relation is a view that presents the currently selected collection
        // (from the doc outline tree view) as the root node with its associated objects as the
        // root node's children
        let inspectorCollectionItems = selectedCollection
            .join(MakeRelation(["parent", "order"], [.NULL, 5.0]))
        let inspectorObjectItems = selectedCollectionID
            .join(objects)
            .renameAttributes(["coll_id": "parent"])
        self.inspectorItems = inspectorCollectionItems
            .union(inspectorObjectItems)
        self.selectedInspectorItems = selectedInspectorItemIDs
            .equijoin(inspectorItems, matching: ["item_id": "id"])
            .project(["id", "type", "name"])
        
        // The `selectedItems` relation is a roll-up view that includes the currently selected
        // inspector item(s) (if non-empty) OR the currently selected doc outline item
        self.selectedItems = selectedInspectorItems.otherwise(selectedCollection)

        // Prepare the tree properties
        self.docOutlineTree = collections.treeProperty()
        self.inspectorItemsTree = inspectorItems.treeProperty()
        
        self.db = db
        self.undoableDB = UndoableDatabase(db: db, undoManager: undoManager)

//        self.removal = selectedItems.addChangeObserver({ changes in
//            print("ADDS:\n\(changes.added)")
//            print("REMOVES:\n\(changes.removed)")
//            print("SELECTED ITEMS:\n\(self.selectedItems)\n")
//        })
    }
    
    func addDefaultData() {
        func addCollection(collectionID: Int64, name: String, type: ItemType, parentID: Int64?, order: Double) {
            db.transaction({
                self.addCollection(collectionID, name: name, type: type, parentID: parentID, order: order)
            })
        }
        
        addCollection(1, name: "Group1", type: .Group, parentID: nil, order: 5.0)
        addCollection(2, name: "Collection1", type: .Collection, parentID: 1, order: 5.0)
        addCollection(3, name: "Page1", type: .Page, parentID: 1, order: 7.0)
        addCollection(4, name: "Page2", type: .Page, parentID: 1, order: 8.0)
        addCollection(5, name: "Child1", type: .Page, parentID: 2, order: 5.0)
        addCollection(6, name: "Child2", type: .Page, parentID: 2, order: 7.0)
        addCollection(7, name: "Group2", type: .Group, parentID: nil, order: 7.0)
        
        func addObject(objectID: Int64, name: String, type: ItemType, collectionID: Int64, order: Double) {
            db.transaction({
                self.addObject(objectID, name: name, type: type, collectionID: collectionID, order: order)
            })
        }
        
        addObject(8, name: "Text1", type: .Text, collectionID: 3, order: 5.0)
        addObject(9, name: "Text2", type: .Text, collectionID: 3, order: 7.0)
        addObject(10, name: "Image1", type: .Image, collectionID: 3, order: 8.0)
        globalID = 11
    }
    
    private func performUndoableAction(name: String, _ transactionFunc: Void -> Void) {
        performUndoableAction(name, before: nil, transactionFunc)
    }
    
    private func performUndoableAction(name: String, before: ChangeLoggingDatabaseSnapshot?, _ transactionFunc: Void -> Void) {
        undoableDB.performUndoableAction(name, before: before, transactionFunc)
    }
    
    private func addCollection(collectionID: Int64, name: String, type: ItemType, parentID: Int64?, previousID: Int64?) {
        let row: Row = [
            "id": RelationValue(collectionID),
            "type": RelationValue(type.rawValue),
            "name": RelationValue(name)
        ]
        let parent = parentID.map{RelationValue($0)}
        let previous = previousID.map{RelationValue($0)}
        let pos: TreePos<RowTreeNode> = TreePos(parentID: parent, previousID: previous, nextID: nil)
        docOutlineTree.insert(row, pos: pos)
    }

    /// For testing purposes only.
    internal func addCollection(collectionID: Int64, name: String, type: ItemType, parentID: Int64?, order: Double) {
        let parentIDValue = parentID.map{ RelationValue($0) } ?? .NULL
        let row: Row = [
            "id": RelationValue(collectionID),
            "type": RelationValue(type.rawValue),
            "name": RelationValue(name),
            "parent": parentIDValue,
            "order": RelationValue(order)
        ]
        collections.add(row)
    }

    internal func addObject(objectID: Int64, name: String, type: ItemType, collectionID: Int64, order: Double) {
        objects.add([
            "id": RelationValue(objectID),
            "name": RelationValue(name),
            "type": RelationValue(type.rawValue),
            "coll_id": RelationValue(collectionID),
            "order": RelationValue(order)
        ])
        
        switch type {
        case .Text:
            textObjects.add([
                "id": RelationValue(objectID),
                "editable": 0,
                "hint": RelationValue("Hint for \(name)"),
                "font": .NULL
            ])
        case .Image:
            imageObjects.add([
                "id": RelationValue(objectID),
                "editable": 0
            ])
        default:
            break
        }
    }

    func newCollection(name: String, type: ItemType, parentID: Int64?) {
        let id = globalID
        globalID += 1
        performUndoableAction("New \(type.name)", {
            self.addCollection(id, name: name, type: type, parentID: parentID, previousID: nil)
        })
    }
    
    func newObject(name: String, type: ItemType, collectionID: Int64, order: Double) {
        let id = globalID
        globalID += 1
        performUndoableAction("New \(type.name)", {
            self.addObject(id, name: name, type: type, collectionID: collectionID, order: order)
        })
    }
    
    func deleteCollection(id: RelationValue, type: ItemType) {
        performUndoableAction("Delete \(type.name)", {
            self.docOutlineTree.delete(id)
        })
    }

    lazy var docOutlineTreeViewModel: TreeViewModel<RowTreeNode> = { [unowned self] in
        return TreeViewModel(
            data: self.docOutlineTree,
            allowsChildren: { row in
                let type = ItemType(row)!
                return type == .Group || type == .Collection
            },
            contextMenu: { row in
                let collectionID = row["id"]
                let collectionType = ItemType(row)!
                return ContextMenu(items: [
                    .Titled(title: "New Page", action: { self.newCollection("Page", type: .Page, parentID: nil) }),
                    .Separator,
                    .Titled(title: "Delete", action: { self.deleteCollection(collectionID, type: collectionType) })
                ])
            },
            move: { (srcPath, dstPath) in
                let srcNode = self.docOutlineTree.nodeAtPath(srcPath)!
                let collectionType = ItemType(srcNode.data)!
                self.performUndoableAction("Move \(collectionType.name)", {
                    self.docOutlineTree.move(srcPath: srcPath, dstPath: dstPath)
                })
            },
            selection: self.treeSelectionProperty(self.selectedCollectionID, clearInspectorSelection: true),
            cellIdentifier: { _ in "PageCell" },
            cellText: { row in
                // TODO: Could we have a convenience for creating a projection Relation directly
                // from an existing Row?
                let rowID = row["id"]
                let type = ItemType(row)!
                let nameRelation = self.collections.select(Attribute("id") *== rowID).project(["name"])
                return .AsyncReadWrite(self.nameProperty(nameRelation, type: type.name))
            },
            cellImage: { row in
                let type = ItemType(row)!
                return constantValueProperty(Image(named: type.cellImageName))
            }
        )
    }()

    lazy var inspectorTreeViewModel: TreeViewModel<RowTreeNode> = { [unowned self] in
        return TreeViewModel(
            data: self.inspectorItemsTree,
            allowsChildren: { row in
                let type = ItemType(row)!
                return type.isCollectionType
            },
            contextMenu: nil,
            move: nil,
            selection: self.treeSelectionProperty(self.selectedInspectorItemIDs, clearInspectorSelection: false),
            cellIdentifier: { _ in "PageCell" },
            cellText: { row in
                let rowID = row["id"]
                let type = ItemType(row)!
                let nameRelation = self.inspectorItems.select(Attribute("id") *== rowID).project(["name"])
                return .AsyncReadWrite(self.nameProperty(nameRelation, type: type.name))
            },
            cellImage: { row in
                let type = ItemType(row)!
                return constantValueProperty(Image(named: type.cellImageName))
            }
        )
    }()
    
    // TODO: This would be better as a ReadWriteProperty that is bidirectionally bound to a check-style MenuItem.
    // For now we declare it as MutableValueProperty so that it can be toggled directly in an NSMenuItem action handler.
    lazy var propertiesSidebarVisible: MutableValueProperty<Bool> = { [unowned self] in
        return mutableValueProperty(true)
    }()
    
    lazy var propertiesModel: PropertiesModel = { [unowned self] in
        return PropertiesModel(
            db: self.undoableDB,
            selectedItems: self.selectedItems,
            textObjects: self.textObjects,
            imageObjects: self.imageObjects
        )
    }()

    private func nameProperty(relation: Relation, type: String) -> AsyncReadWriteProperty<String> {
        return undoableDB.asyncBidiProperty(
            relation,
            action: "Rename \(type)",
            signal: relation.signal{ $0.oneString($1) },
            update: { relation.asyncUpdateString($0) }
        )
    }
    
    private func treeSelectionProperty(relation: TransactionalRelation, clearInspectorSelection: Bool) -> AsyncReadWriteProperty<Set<RelationValue>> {
        return undoableDB.asyncBidiProperty(
            relation,
            action: "Change Selection",
            signal: relation.signal{ $0.allValues($1) },
            update: {
                if clearInspectorSelection {
                    self.selectedInspectorItemIDs.asyncDelete(true)
                }
                relation.asyncReplaceValues(Array($0))
            }
        )
    }
}
