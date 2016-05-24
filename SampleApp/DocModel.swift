//
//  DocModel.swift
//  Relational
//
//  Created by Chris Campbell on 5/2/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Foundation
import libRelational

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

    private let undoManager: UndoManager
    private let db: TransactionalDatabase

    private var collections: MutableRelation
    private var objects: MutableRelation
    private var textObjects: MutableRelation
    private var selectedCollectionID: MutableRelation
    private var selectedInspectorItemIDs: MutableRelation
    
    private let inspectorItems: Relation
    private let selectedCollection: Relation
    private let selectedInspectorItems: Relation
    private let selectedItems: Relation

    private let docOutlineBinding: RelationTreeBinding
    private let inspectorItemsBinding: RelationTreeBinding
    
    // TODO: To simplify implementation of the relation that controls the inspector tree view,
    // we put identifiers for both the `collection` and `object` relations into the same set.
    // A potentially better/safer alternative would be to introduce compound primary key
    // support into RelationTreeBinding so that we can more easily merge data from different
    // source relations into a single relation.
    private var globalID: Int64 = 1
    
    private var removal: (Void -> Void)!
    
    init(undoManager: UndoManager) {
        self.undoManager = undoManager
        
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
        func createRelation(name: String, _ scheme: Scheme) -> MutableRelation {
            let createResult = sqliteDB.createRelation(name, scheme: scheme)
            precondition(createResult.ok != nil)
            return db[name]
        }
        self.collections = createRelation("collection", ["id", "type", "name", "parent", "order"])
        self.objects = createRelation("object", ["id", "type", "name", "coll_id", "order"])
        self.textObjects = createRelation("text_object", ["id", "editable", "hint"])
        self.selectedCollectionID = createRelation("selected_collection", ["coll_id"])
        self.selectedInspectorItemIDs = createRelation("selected_inspector_item", ["item_id"])

        // Prepare the higher level relations
        self.selectedCollection = collections
            .renameAttributes(["id" : "coll_id"])
            .join(selectedCollectionID)
        
        // The `inspectorItems` relation is a view that presents the currently selected collection
        // (from the doc outline tree view) as the root node with its associated objects as the
        // root node's children
        // TODO: This is probably more complex than it needs to be
        let inspectorCollectionItems = selectedCollection
            .project(["coll_id", "type", "name"])
            .renameAttributes(["coll_id": "id"])
            .join(MakeRelation(["parent", "order"], [.NULL, 5.0]))
        let inspectorObjectItems = selectedCollectionID
            .project(["coll_id"])
            .join(objects)
            .renameAttributes(["coll_id": "parent"])
            .project(["id", "type", "name", "parent", "order"])
        self.inspectorItems = inspectorCollectionItems
            .union(inspectorObjectItems)
        self.selectedInspectorItems = inspectorItems
            .renameAttributes(["id" : "item_id"])
            .join(selectedInspectorItemIDs)
        
        // The `selectedItems` relation is a roll-up view that includes the currently selected
        // inspector item(s) and/or the currently selected doc outline item.  The inspector item(s)
        // have a higher priority value associated with them, so that finding the currently selected
        // items is just a matter of choosing the rows with the highest priority value.
        let selectedCollectionWithPriority = selectedCollection
            .renameAttributes(["coll_id": "id"])
            .project(["id", "type", "name"])
            .join(MakeRelation(["priority"], [1]))
        let selectedInspectorItemsWithPriority = selectedInspectorItems
            .renameAttributes(["item_id": "id"])
            .project(["id", "type", "name"])
            .join(MakeRelation(["priority"], [2]))
        let allSelectedItems = selectedCollectionWithPriority
            .union(selectedInspectorItemsWithPriority)
        self.selectedItems = allSelectedItems
            .max("priority")
            .join(allSelectedItems)

        // Prepare the tree bindings
        self.docOutlineBinding = RelationTreeBinding(relation: collections, idAttr: "id", parentAttr: "parent", orderAttr: "order")
        self.inspectorItemsBinding = RelationTreeBinding(relation: inspectorItems, idAttr: "id", parentAttr: "parent", orderAttr: "order")
        
        self.db = db

        self.removal = selectedItems.addChangeObserver({ changes in
//            print("ADDS:\n\(changes.added)")
//            print("REMOVES:\n\(changes.removed)")
            print("ITEMS:\n\(self.selectedItems)\n")
        })
    }
    
    func addDefaultData() {
        func addCollection(collectionID: Int64, name: String, type: ItemType, parentID: Int64?, previousID: Int64?) {
            db.transaction({
                self.addCollection(collectionID, name: name, type: type, parentID: parentID, previousID: previousID)
            })
        }
        
        addCollection(1, name: "Group1", type: .Group, parentID: nil, previousID: nil)
        addCollection(2, name: "Collection1", type: .Collection, parentID: 1, previousID: nil)
        addCollection(3, name: "Page1", type: .Page, parentID: 1, previousID: 2)
        addCollection(4, name: "Page2", type: .Page, parentID: 1, previousID: 3)
        addCollection(5, name: "Child1", type: .Page, parentID: 2, previousID: nil)
        addCollection(6, name: "Child2", type: .Page, parentID: 2, previousID: 5)
        addCollection(7, name: "Group2", type: .Group, parentID: nil, previousID: 1)
        
        func addObject(objectID: Int64, name: String, type: ItemType, collectionID: Int64, order: Double) {
            db.transaction({
                self.addObject(objectID, name: name, type: type, collectionID: collectionID, order: order)
            })
        }
        
        addObject(8, name: "Text1", type: .Text, collectionID: 3, order: 5.0)
        addObject(9, name: "Image1", type: .Image, collectionID: 3, order: 7.0)
        globalID = 10
    }
    
    private func performUndoableAction(name: String, _ transactionFunc: Void -> Void) {
        performUndoableAction(name, before: nil, transactionFunc)
    }
    
    private func performUndoableAction(name: String, before: ChangeLoggingDatabaseSnapshot?, _ transactionFunc: Void -> Void) {
        let before = before ?? db.takeSnapshot()
        db.transaction(transactionFunc)
        let after = db.takeSnapshot()

        undoManager.registerChange(
            name: name,
            perform: false,
            forward: {
                self.db.restoreSnapshot(after)
            },
            backward: {
                self.db.restoreSnapshot(before)
            }
        )
    }
    
    private func addCollection(collectionID: Int64, name: String, type: ItemType, parentID: Int64?, previousID: Int64?) {
        let row: Row = [
            "id": RelationValue(collectionID),
            "type": RelationValue(type.rawValue),
            "name": RelationValue(name)
        ]
        let parent = parentID.map{RelationValue($0)}
        let previous = previousID.map{RelationValue($0)}
        let pos = RelationTreeBinding.Pos(parentID: parent, previousID: previous, nextID: nil)
        docOutlineBinding.insert(row, pos: pos)
    }
    
    private func addObject(objectID: Int64, name: String, type: ItemType, collectionID: Int64, order: Double) {
        objects.add([
            "id": RelationValue(objectID),
            "name": RelationValue(name),
            "type": RelationValue(type.rawValue),
            "coll_id": RelationValue(collectionID),
            "order": RelationValue(order)
        ])
        
        if type == .Text {
            textObjects.add([
                "id": RelationValue(objectID),
                "editable": 0,
                "hint": ""
            ])
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
            self.docOutlineBinding.delete(id)
        })
    }

    lazy var docOutlineTreeViewModel: TreeViewModel<Row> = { [unowned self] in
        return TreeViewModel(
            data: self.docOutlineBinding,
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
                let srcNode = self.docOutlineBinding.nodeAtPath(srcPath)!
                let collectionType = ItemType(srcNode.data)!
                self.performUndoableAction("Move \(collectionType.name)", {
                    self.docOutlineBinding.move(srcPath: srcPath, dstPath: dstPath)
                })
            },
            selection: self.bidiSelectionBinding(self.selectedCollectionID),
            cellText: { row in
                // TODO: Could we have a convenience for creating a projection Relation directly
                // from an existing Row?
                let rowID = row["id"]
                let type = ItemType(row)!
                let nameRelation = self.collections.select(Attribute("id") *== rowID).project(["name"])
                return self.bidiStringBinding(nameRelation, type: type.name)
            }
        )
    }()

    lazy var inspectorTreeViewModel: TreeViewModel<Row> = { [unowned self] in
        return TreeViewModel(
            data: self.inspectorItemsBinding,
            allowsChildren: { row in
                let type = ItemType(row)!
                return type.isCollectionType
            },
            contextMenu: nil,
            move: nil,
            selection: self.bidiSelectionBinding(self.selectedInspectorItemIDs),
            cellText: { row in
                let rowID = row["id"]
                let type = ItemType(row)!
                let nameRelation = self.inspectorItems.select(Attribute("id") *== rowID).project(["name"])
                return self.bidiStringBinding(nameRelation, type: type.name)
            }
        )
    }()

    private lazy var selectedItemNamesRelation: Relation = { [unowned self] in
        return self.selectedItems.project(["name"])
    }()

    private lazy var selectedItemTypesRelation: Relation = { [unowned self] in
        return self.selectedItems.project(["type"])
    }()

    lazy var itemSelected: ValueBinding<Bool> = { [unowned self] in
        return self.selectedItems.nonEmpty
    }()
    
    lazy var itemNotSelected: ValueBinding<Bool> = { [unowned self] in
        return self.selectedItems.empty
    }()
    
    lazy var selectedItemTypes: ValueBinding<[ItemType]> = { [unowned self] in
        return self.selectedItemTypesRelation.all{ ItemType($0)! }
    }()
    
    lazy var selectedItemTypesString: ValueBinding<String> = { [unowned self] in
        // TODO: Is there a more efficient way to do this?
        let selectedItemCountBinding = self.selectedItems.count().oneInteger
        return selectedItemCountBinding.zip(self.selectedItemTypes).map { (count, types) in
            if types.count == 0 {
                return ""
            } else if count == 1 {
                return types.first!.name
            } else {
                if types.count == 1 {
                    return "Multiple \(types.first!.name)s"
                } else {
                    return "Multiple Items"
                }
            }
        }
    }()
    
    lazy var selectedItemNames: BidiValueBinding<String> = { [unowned self] in
        // TODO: s/Item/type.name/
        return self.bidiStringBinding(self.selectedItemNamesRelation, type: "Item")
    }()

    lazy var selectedItemNamesPlaceholder: ValueBinding<String> = { [unowned self] in
        return self.selectedItemNamesRelation.stringWhenMulti("Multiple Values")
    }()

    lazy var selectedItemsOnlyText: ValueBinding<Bool> = { [unowned self] in
        return self.selectedItemTypes.isOne(.Text)
    }()
    
//    private lazy var selectedTextObjects: Relation = { [unowned self] in
//        return Relation.when(self.selectedItemsOnlyText, then: {
//            self.selectedItems
//                .project(["id"])
//                .join(self.textObjects)
//        })
//    }()
    
//    // TODO: Bidi
//    lazy var selectedTextObjectsEditable: ValueBinding<Bool?> = { [unowned self] in
//        return self.selectedTextObjects
//            .project(["editable"])
//            .oneBoolOrNil
//            .onlyWhen(self.selectedItemsOnlyText)
//    }()

//    // TODO: Bidi
//    lazy var selectedTextObjectsHint: ValueBinding<String> = { [unowned self] in
//        return self.selectedTextObjects
//            .project(["hint"])
//            .oneBoolOrNil
//            .onlyWhen(self.selectedItemsOnlyText)
//    }()

    lazy var selectedItemsOnlyImage: ValueBinding<Bool> = { [unowned self] in
        return self.selectedItemTypes.isOne(.Image)
    }()

    private func bidiStringBinding(relation: Relation, type: String) -> BidiValueBinding<String> {
        func update(newValue: String) {
            let attr = relation.scheme.attributes.first!
            let values: Row = [attr: RelationValue(newValue)]
            var mutableRelation = relation
            let updateResult = mutableRelation.update(true, newValues: values)
            precondition(updateResult.ok != nil)
        }

        return relation.bidiString(RelationBidiConfig(
            snapshot: {
                return self.db.takeSnapshot()
            },
            update: { newValue in
                update(newValue)
            },
            commit: { before, newValue in
                self.performUndoableAction("Rename \(type)", before: before, {
                    update(newValue)
                })
            }
        ))
    }
    
    private func bidiSelectionBinding(relation: MutableRelation) -> BidiValueBinding<[RelationValue]> {
        func update(newValues: [RelationValue]) {
            let attr = relation.scheme.attributes.first!
            var mutableRelation = relation
            mutableRelation.delete(true)
            for id in newValues {
                mutableRelation.add([attr: id])
            }
        }
        
        return relation.bidiValues(RelationBidiConfig(
            snapshot: {
                return self.db.takeSnapshot()
            },
            update: { newValues in
                // TODO: We wrap this in a transaction to keep it atomic, but we don't actually
                // need to log the changes anywhere
                self.db.transaction({
                    update(newValues)
                })
            },
            commit: { before, newValues in
                self.performUndoableAction("Change Selection", before: before, {
                    update(newValues)
                })
            }
        ))
    }
}
