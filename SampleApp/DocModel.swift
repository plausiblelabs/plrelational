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

struct DocItem {
    let id: RelationValue
    let type: ItemType
}

class DocModel {

    typealias Transaction = ChangeLoggingDatabase.Transaction
    
    private let undoManager: UndoManager
    private let db: ChangeLoggingDatabase

    private let collections: Relation
    private let objects: Relation
    private let inspectorItems: Relation
    private let selectedCollectionID: Relation
    private let selectedInspectorItemID: Relation
    
    private let selectedCollection: Relation
    private let selectedInspectorItem: Relation
    
    private let docOutlineBinding: OrderedTreeBinding
    private let inspectorItemsBinding: OrderedTreeBinding
    
    // TODO: To simplify implementation of the relation that controls the inspector tree view,
    // we put identifiers for both the `collection` and `object` relations into the same set.
    // A potentially better/safer alternative would be to introduce compound primary key
    // support into OrderedTreeBinding so that we can more easily merge data from different
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
        let db = ChangeLoggingDatabase(sqliteDB)
        func createRelation(name: String, _ scheme: Scheme) -> ChangeLoggingRelation<SQLiteTableRelation> {
            let createResult = sqliteDB.createRelation(name, scheme: scheme)
            precondition(createResult.ok != nil)
            return db[name]
        }
        self.collections = createRelation("collection", ["id", "type", "name", "parent", "order"])
        self.objects = createRelation("object", ["id", "type", "name", "coll_id", "order"])
        self.selectedCollectionID = createRelation("selected_collection", ["id", "coll_id"])
        self.selectedInspectorItemID = createRelation("selected_inspector_item", ["id", "item_id"])

        // Prepare the higher level relations
        self.selectedCollection = collections.renameAttributes(["id" : "coll_id"]).join(selectedCollectionID)
        
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
        self.inspectorItems = inspectorCollectionItems.union(inspectorObjectItems)
        self.selectedInspectorItem = inspectorItems.renameAttributes(["id" : "item_id"]).join(selectedInspectorItemID)
        
        // Prepare the tree bindings
        self.docOutlineBinding = OrderedTreeBinding(relation: collections, tableName: "collection", idAttr: "id", parentAttr: "parent", orderAttr: "order")
        self.inspectorItemsBinding = OrderedTreeBinding(relation: inspectorItems, tableName: "", idAttr: "id", parentAttr: "parent", orderAttr: "order")
        
        self.db = db

        self.removal = inspectorItems.addChangeObserver({ _ in
            print("COLLS:\n\(inspectorCollectionItems)\n")
            print("OBJS:\n\(inspectorObjectItems)\n")
            print("ITEMS:\n\(self.inspectorItems)\n")
        })
    }
    
    func addDefaultData() {
        func addCollection(collectionID: Int64, name: String, type: ItemType, parentID: Int64?, previousID: Int64?) {
            db.transaction({
                self.addCollection($0, collectionID: collectionID, name: name, type: type, parentID: parentID, previousID: previousID)
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
                self.addObject($0, objectID: objectID, name: name, type: type, collectionID: collectionID, order: order)
            })
        }
        
        addObject(8, name: "Text1", type: .Text, collectionID: 3, order: 5.0)
        addObject(9, name: "Image1", type: .Image, collectionID: 3, order: 7.0)
        globalID = 10
    }
    
    private func performUndoableAction(name: String, _ transactionFunc: Transaction -> Void) {
        let (before, after) = db.transactionWithSnapshots(transactionFunc)
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
    
    private func addCollection(transaction: Transaction, collectionID: Int64, name: String, type: ItemType, parentID: Int64?, previousID: Int64?) {
        let row: Row = [
            "id": RelationValue(collectionID),
            "type": RelationValue(type.rawValue),
            "name": RelationValue(name)
        ]
        let parent = parentID.map{RelationValue($0)}
        let previous = previousID.map{RelationValue($0)}
        let pos = TreePos(parentID: parent, previousID: previous, nextID: nil)
        docOutlineBinding.insert(transaction, row: row, pos: pos)
    }
    
    private func addObject(transaction: Transaction, objectID: Int64, name: String, type: ItemType, collectionID: Int64, order: Double) {
        let objects = transaction["object"]
        let row: Row = [
            "id": RelationValue(objectID),
            "name": RelationValue(name),
            "type": RelationValue(type.rawValue),
            "coll_id": RelationValue(collectionID),
            "order": RelationValue(order)
        ]
        objects.add(row)
    }

    func newCollection(name: String, type: ItemType, parentID: Int64?) {
        let id = globalID
        globalID += 1
        performUndoableAction("New \(type.name)", {
            self.addCollection($0, collectionID: id, name: name, type: type, parentID: parentID, previousID: nil)
        })
    }
    
    func newObject(name: String, type: ItemType, collectionID: Int64, order: Double) {
        let id = globalID
        globalID += 1
        performUndoableAction("New \(type.name)", {
            self.addObject($0, objectID: id, name: name, type: type, collectionID: collectionID, order: order)
        })
    }
    
    func deleteCollection(id: RelationValue, type: ItemType) {
        performUndoableAction("Delete \(type.name)", {
            self.docOutlineBinding.delete($0, id: id)
        })
    }

    private func selectCollection(id: RelationValue, update: Bool) {
        // TODO: s/Collection/type.name/
        self.performUndoableAction("Select Collection", {
            let selectedCollection = $0["selected_collection"]
            if update {
                selectedCollection.update(Attribute("id") *== RelationValue(Int64(1)), newValues: ["coll_id": id])
            } else {
                selectedCollection.add(["id": RelationValue(Int64(1)), "coll_id": id])
            }
        })
    }
    
    private func deselectCollection() {
        // TODO: s/Collection/type.name/
        self.performUndoableAction("Deselect Collection", {
            let selectedCollection = $0["selected_collection"]
            selectedCollection.delete(Attribute("id") *== RelationValue(Int64(1)))
        })
    }

    private func selectInspectorItem(id: RelationValue, update: Bool) {
        // TODO: s/Object/type.name/
        self.performUndoableAction("Select Object", {
            let selectedInspectorItem = $0["selected_inspector_item"]
            if update {
                selectedInspectorItem.update(Attribute("id") *== RelationValue(Int64(1)), newValues: ["item_id": id])
            } else {
                selectedInspectorItem.add(["id": RelationValue(Int64(1)), "item_id": id])
            }
        })
    }
    
    private func deselectInspectorItem() {
        // TODO: s/Object/type.name/
        self.performUndoableAction("Deselect Object", {
            let selectedInspectorItem = $0["selected_inspector_item"]
            selectedInspectorItem.delete(Attribute("id") *== RelationValue(Int64(1)))
        })
    }
    
    lazy var docOutlineTreeViewModel: TreeViewModel = { [unowned self] in
        let data = TreeViewModel.Data(
            binding: self.docOutlineBinding,
            allowsChildren: { row in
                let type = ItemType(rawValue: row["type"].get()!)!
                return type == .Group || type == .Collection
            },
            contextMenu: { row in
                let collectionID = row["id"]
                let collectionType = ItemType(rawValue: row["type"].get()!)!
                return ContextMenu(items: [
                    .Titled(title: "New Page", action: { self.newCollection("Page", type: .Page, parentID: nil) }),
                    .Separator,
                    .Titled(title: "Delete", action: { self.deleteCollection(collectionID, type: collectionType) })
                ])
            },
            move: { (srcPath, dstPath) in
                // TODO: s/Collection/type.name/
                self.performUndoableAction("Move Collection", {
                    self.docOutlineBinding.move($0, srcPath: srcPath, dstPath: dstPath)
                })
            }
        )
        
        let selection = TreeViewModel.Selection(
            relation: self.selectedCollection,
            set: { id in
                let selectedID = self.selectedCollectionID.rows().next().map{$0.ok!["coll_id"]}
                if let id = id {
                    self.selectCollection(id, update: selectedID != nil)
                } else {
                    self.deselectCollection()
                }
            },
            get: {
                return self.selectedCollectionID.rows().next().map{$0.ok!["coll_id"]}
            }
        )
        
        let cell = { (row: Row) -> TreeViewModel.Cell in
            // TODO: Ideally we'd have a way to create a projection Relation directly from
            // an existing Row.  In the meantime, we'll select/project from the original
            // relation.  The downside of that latter approach is that the cell text will
            // disappear before the cell fades out in the case where the item is deleted.
            // (If the cell was bound to a projection of the row, presumably it would
            // continue to work even after the row has been deleted from the underlying
            // relation.)
            let rowID = row["id"]
            let nameRelation = self.collections.select(Attribute("id") *== rowID).project(["name"])
            // TODO: s/Collection/type.name/
            let binding = self.bidiBinding(nameRelation, attr: "name", type: "Collection")
            return TreeViewModel.Cell(text: binding)
        }
        
        return TreeViewModel(data: data, selection: selection, cell: cell)
    }()

    lazy var inspectorTreeViewModel: TreeViewModel = { [unowned self] in
        let data = TreeViewModel.Data(
            binding: self.inspectorItemsBinding,
            allowsChildren: { row in
                let type = ItemType(rawValue: row["type"].get()!)!
                return type.isCollectionType
            },
            contextMenu: nil,
            move: nil
        )
        
        let selection = TreeViewModel.Selection(
            relation: self.selectedInspectorItem,
            set: { id in
                let selectedID = self.selectedInspectorItemID.rows().next().map{$0.ok!["item_id"]}
                if let id = id {
                    self.selectInspectorItem(id, update: selectedID != nil)
                } else {
                    self.deselectInspectorItem()
                }
            },
            get: {
                return self.selectedInspectorItemID.rows().next().map{$0.ok!["item_id"]}
            }
        )
        
        let cell = { (row: Row) -> TreeViewModel.Cell in
            let rowID = row["id"]
            let nameRelation = self.inspectorItems.select(Attribute("id") *== rowID).project(["name"])
            // TODO: s/Object/type.name/
            let binding = self.bidiBinding(nameRelation, attr: "name", type: "Object")
            return TreeViewModel.Cell(text: binding)
        }
        
        return TreeViewModel(data: data, selection: selection, cell: cell)
    }()
    
    private lazy var selectedCollectionDocItem: ValueBinding<DocItem?> = { [unowned self] in
        return SingleRowBinding(relation: self.selectedCollection).map{ row in
            if let row = row {
                let id = row["coll_id"]
                let type = ItemType(rawValue: row["type"].get()!)!
                return DocItem(id: id, type: type)
            } else {
                return nil
            }
        }
    }()

    private lazy var selectedInspectorDocItem: ValueBinding<DocItem?> = { [unowned self] in
        return SingleRowBinding(relation: self.selectedInspectorItem).map{ row in
            if let row = row {
                let id = row["item_id"]
                let type = ItemType(rawValue: row["type"].get()!)!
                return DocItem(id: id, type: type)
            } else {
                return nil
            }
        }
    }()
    
    private lazy var selectedDocItem: ValueBinding<DocItem?> = { [unowned self] in
        return self.selectedCollectionDocItem.zip(self.selectedInspectorDocItem).map{ (docItem, inspectorItem) in
            return inspectorItem ?? docItem
        }
    }()
    
    lazy var itemSelected: ValueBinding<Bool> = { [unowned self] in
        return self.selectedDocItem.map{ $0 != nil }
    }()
    
    lazy var itemNotSelected: ValueBinding<Bool> = { [unowned self] in
        return self.selectedDocItem.map{ $0 == nil }
    }()

    lazy var selectedItemType: ValueBinding<String?> = { [unowned self] in
        return self.selectedDocItem.map{ $0?.type.name }
    }()
    
    // TODO: This should resolve to the name associated with selectedDocItem
    lazy var selectedItemName: StringBidiBinding = { [unowned self] in
        let nameRelation = self.selectedCollection.project(["name"])
        // TODO: s/Collection/type.name/
        return self.bidiBinding(nameRelation, attr: "name", type: "Collection")
    }()
    
    private func bidiBinding(relation: Relation, attr: Attribute, type: String) -> StringBidiBinding {
        
        func update(newValue: String) {
            let values: Row = [attr: RelationValue(newValue)]
            Swift.print("UPDATE: \(newValue)")
            var mutableRelation = relation
            let updateResult = mutableRelation.update(true, newValues: values)
            precondition(updateResult.ok != nil)
        }
        
        return StringBidiBinding(relation: relation, change: BidiChange<String>{ (newValue, oldValue, commit) in
            Swift.print("\(commit ? "COMMIT" : "CHANGE") new=\(newValue) old=\(oldValue)")
            if commit {
                self.undoManager.registerChange(
                    name: "Rename \(type)",
                    perform: true,
                    forward: { update(newValue) },
                    backward: { update(oldValue) }
                )
            } else {
                update(newValue)
            }
        })
    }
}
