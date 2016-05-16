//
//  DocModel.swift
//  Relational
//
//  Created by Chris Campbell on 5/2/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Foundation
import libRelational

enum DocItem { case
    Page(RelationValue),
    Object(RelationValue)
    
    var typeName: String {
        switch self {
        case .Page:
            return "Page"
        case .Object:
            return "Object"
        }
    }
}

enum CollectionType: Int64 { case
    Group = 0,
    Collection = 1,
    Page = 2
    
    var name: String {
        switch self {
        case .Group: return "Group"
        case .Collection: return "Collection"
        case .Page: return "Page"
        }
    }
}

class DocModel {

    typealias Transaction = ChangeLoggingDatabase.Transaction
    
    private let undoManager: UndoManager
    private let db: ChangeLoggingDatabase
    private let collections: Relation
    private let objects: Relation
    private let inspectorItems: Relation
    private let selectedCollection: Relation
    private let selectedInspectorItem: Relation
    private let selectedCollectionItem: Relation
    
    private let docOutlineBinding: OrderedTreeBinding
    private let inspectorItemsBinding: OrderedTreeBinding
    
    private var collectionID: Int64 = 1
    private var objectID: Int64 = 1001
    
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
        
        // Prepare the schemas
        let sqliteDB = makeDB().db
        let db = ChangeLoggingDatabase(sqliteDB)
        func createRelation(name: String, _ scheme: Scheme) -> ChangeLoggingRelation<SQLiteTableRelation> {
            let createResult = sqliteDB.createRelation(name, scheme: scheme)
            precondition(createResult.ok != nil)
            return db[name]
        }
        self.collections = createRelation("collection", ["id", "type", "name", "parent", "order"])
        self.objects = createRelation("object", ["id", "name", "coll_id", "order"])
        self.selectedCollection = createRelation("selected_collection", ["id", "coll_id"])
        self.selectedInspectorItem = createRelation("selected_inspector_item", ["id", "type", "fid"])
        self.selectedCollectionItem = collections.renameAttributes(["id" : "coll_id"]).join(selectedCollection)

        // Prepare the tree bindings
        self.docOutlineBinding = OrderedTreeBinding(relation: collections, tableName: "collection", idAttr: "id", parentAttr: "parent", orderAttr: "order")

        // XXX
        let inspectorCollectionItems = selectedCollection
            .project(["coll_id"])
            .renameAttributes(["coll_id": "id"])
            .join(collections)
            .renameAttributes(["id": "fid"])
            .project(["fid", "name"])
            .join(MakeRelation(["id", "parent", "order"], [1, .NULL, 5.0]))
        
        let inspectorObjectItems = selectedCollection
            .project(["coll_id"])
            .join(objects)
            .renameAttributes(["id": "fid"])
            .project(["fid", "name", "order"])
            .join(MakeRelation(["id", "parent"], [2, 1]))
        
        self.inspectorItems = inspectorCollectionItems.union(inspectorObjectItems)
        self.inspectorItemsBinding = OrderedTreeBinding(relation: inspectorItems, tableName: "", idAttr: "id", parentAttr: "parent", orderAttr: "order")
        
        self.db = db

        self.removal = inspectorItems.addChangeObserver({ _ in
            print("COLLS:\n\(inspectorCollectionItems)\n")
            print("OBJS:\n\(inspectorObjectItems)\n")
            print("ITEMS:\n\(self.inspectorItems)\n")
        })
    }
    
    func addDefaultData() {
        func addCollection(collectionID: Int64, name: String, type: CollectionType, parentID: Int64?, previousID: Int64?) {
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
        collectionID = 8
        
        func addObject(objectID: Int64, _ name: String, _ collectionID: Int64, _ order: Double) {
            db.transaction({
                self.addObject($0, objectID: objectID, name: name, collectionID: collectionID, order: order)
            })
        }
        
        addObject(1001, "Obj1", 3, 5.0)
        addObject(1002, "Obj2", 4, 5.0)
        objectID = 1003
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
    
    private func addCollection(transaction: Transaction, collectionID: Int64, name: String, type: CollectionType, parentID: Int64?, previousID: Int64?) {
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
    
    private func addObject(transaction: Transaction, objectID: Int64, name: String, collectionID: Int64, order: Double) {
        let objects = transaction["object"]
        let row: Row = [
            "id": RelationValue(objectID),
            "name": RelationValue(name),
            "coll_id": RelationValue(collectionID),
            "order": RelationValue(order)
        ]
        objects.add(row)
    }
    
    func newObject(name: String, collectionID: Int64, order: Double) {
        let id = objectID
        objectID += 1
        performUndoableAction("New Object", {
            self.addObject($0, objectID: id, name: name, collectionID: collectionID, order: order)
        })
    }
    
    func newCollection(name: String, type: CollectionType, parentID: Int64?) {
        let id = collectionID
        collectionID += 1
        performUndoableAction("New \(type.name)", {
            self.addCollection($0, collectionID: id, name: name, type: type, parentID: parentID, previousID: nil)
        })
    }
    
    func deleteCollection(id: RelationValue, type: CollectionType) {
        performUndoableAction("Delete \(type.name)", {
            self.docOutlineBinding.delete($0, id: id)
        })
    }

    private func selectCollection(id: RelationValue, update: Bool) {
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
        self.performUndoableAction("Deselect Collection", {
            let selectedCollection = $0["selected_collection"]
            selectedCollection.delete(Attribute("id") *== RelationValue(Int64(1)))
        })
    }

    lazy var docOutlineTreeViewModel: TreeViewModel = { [unowned self] in
        let data = TreeViewModel.Data(
            binding: self.docOutlineBinding,
            allowsChildren: { row in
                let rawType: Int64 = row["type"].get()!
                return rawType != CollectionType.Page.rawValue
            },
            contextMenu: { row in
                let collectionID = row["id"]
                let collectionType = CollectionType(rawValue: row["type"].get()!)!
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
        
        // TODO: s/Collection/type.name/
        let selection = TreeViewModel.Selection(
            relation: self.selectedCollection,
            set: { id in
                let selectedID = self.selectedCollection.rows().next().map{$0.ok!["coll_id"]}
                if let id = id {
                    self.selectCollection(id, update: selectedID != nil)
                } else {
                    self.deselectCollection()
                }
            },
            get: {
                return self.selectedCollection.rows().next().map{$0.ok!["coll_id"]}
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
                // XXX
                let rowID: Int64 = row["id"].get()!
                return rowID != 1
            },
            contextMenu: nil,
            move: nil
        )
        
        let selection = TreeViewModel.Selection(
            // TODO
            relation: self.selectedCollection,
            set: { _ in
                // TODO
            },
            get: {
                return nil
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
    
    lazy var itemSelected: ValueBinding<Bool> = { [unowned self] in
        return self.selectedDocItem.map{ $0 != nil }
    }()
    
    lazy var itemNotSelected: ValueBinding<Bool> = { [unowned self] in
        return self.selectedDocItem.map{ $0 == nil }
    }()

    private lazy var selectedCollectionDocItem: ValueBinding<DocItem?> = { [unowned self] in
        return RelationValueBinding(relation: self.selectedCollectionItem.project(["coll_id"])).map{ value in
            if let id = value {
                return DocItem.Page(id)
            } else {
                return nil
            }
        }
    }()

    private lazy var selectedInspectorDocItem: ValueBinding<DocItem?> = { [unowned self] in
        return SingleRowBinding(relation: self.selectedInspectorItem).map{ row in
            if let row = row {
                let type: Int64 = row["type"].get()!
                let fid: Int64 = row["fid"].get()!
                if type == 0 {
                    return DocItem.Page(RelationValue(fid))
                } else {
                    return DocItem.Object(RelationValue(fid))
                }
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
    
    lazy var selectedItemType: ValueBinding<String?> = { [unowned self] in
        return self.selectedDocItem.map{ $0?.typeName }
    }()
    
    // TODO: This should resolve to the name associated with selectedDocItem
    lazy var selectedItemName: StringBidiBinding = { [unowned self] in
        let nameRelation = self.selectedCollectionItem.project(["name"])
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
