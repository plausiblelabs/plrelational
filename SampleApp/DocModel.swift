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
    private let collections: ChangeLoggingRelation<SQLiteTableRelation>
    private let orderedCollections: OrderedTreeBinding
    private let selectedCollection: ChangeLoggingRelation<SQLiteTableRelation>
    private let selectedInspectorItem: ChangeLoggingRelation<SQLiteTableRelation>
    private let selectedCollectionItem: Relation
    private var collectionID: Int64 = 1
    
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
            assert(sqliteDB.createRelation(name, scheme: scheme).ok != nil)
            return db[name]
        }
        self.collections = createRelation("collection", ["id", "type", "name", "parent", "order"])
        self.orderedCollections = OrderedTreeBinding(relation: collections, tableName: "collection", idAttr: "id", parentAttr: "parent", orderAttr: "order")
        self.selectedCollection = createRelation("selected_collection", ["id", "coll_id"])
        self.selectedInspectorItem = createRelation("selected_inspector_item", ["id", "type", "fid"])
        self.selectedCollectionItem = collections.renameAttributes(["id" : "coll_id"]).join(selectedCollection)
        self.db = db

        func addCollection(collectionID: Int64, name: String, type: CollectionType, parentID: Int64?, previousID: Int64?) {
            db.transaction({
                self.addCollection($0, collectionID: collectionID, name: name, type: type, parentID: parentID, previousID: previousID)
            })
        }
        
        // Prepare the default document data
        addCollection(1, name: "Group1", type: .Group, parentID: nil, previousID: nil)
        addCollection(2, name: "Collection1", type: .Collection, parentID: 1, previousID: nil)
        addCollection(3, name: "Page1", type: .Page, parentID: 1, previousID: 2)
        addCollection(4, name: "Page2", type: .Page, parentID: 1, previousID: 3)
        addCollection(5, name: "Child1", type: .Page, parentID: 2, previousID: nil)
        addCollection(6, name: "Child2", type: .Page, parentID: 2, previousID: 5)
        addCollection(7, name: "Group2", type: .Group, parentID: nil, previousID: 1)
        collectionID = 8
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
        orderedCollections.insert(transaction, row: row, pos: pos)
    }
    
    func newCollection(name: String, type: CollectionType) {
        let id = collectionID
        collectionID += 1
        let previousNodeID: Int64? = orderedCollections.root.children.last?.data["id"].get()
        performUndoableAction("New \(type.name)", {
            self.addCollection($0, collectionID: id, name: name, type: type, parentID: nil, previousID: previousNodeID)
        })
    }
    
    func deleteCollection(id: RelationValue, type: CollectionType) {
        performUndoableAction("Delete \(type.name)", {
            self.orderedCollections.delete($0, id: id)
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
            binding: self.orderedCollections,
            allowsChildren: { row in
                let rawType: Int64 = row["type"].get()!
                return rawType != CollectionType.Page.rawValue
            },
            contextMenu: { row in
                let collectionID = row["id"]
                let collectionType = CollectionType(rawValue: row["type"].get()!)!
                return ContextMenu(items: [
                    .Titled(title: "New Page", action: { self.newCollection("Page", type: .Page) }),
                    .Separator,
                    .Titled(title: "Delete", action: { self.deleteCollection(collectionID, type: collectionType) })
                ])
            },
            move: { (srcPath, dstPath) in
                // TODO: s/Collection/type.name/
                self.performUndoableAction("Move Collection", {
                    self.orderedCollections.move($0, srcPath: srcPath, dstPath: dstPath)
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
            let binding = self.collectionNameBinding(nameRelation)
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
        return self.collectionNameBinding(self.selectedCollectionItem.project(["name"]))
    }()
    
    private func collectionNameBinding(relation: Relation) -> StringBidiBinding {
        
        func update(newValue: String) {
            let values: Row = ["name": RelationValue(newValue)]
            Swift.print("UPDATE: \(newValue)")
            var mutableRelation = relation
            assert(mutableRelation.update(true, newValues: values).ok != nil)
        }
        
        return StringBidiBinding(relation: relation, change: BidiChange<String>{ (newValue, oldValue, commit) in
            Swift.print("\(commit ? "COMMIT" : "CHANGE") new=\(newValue) old=\(oldValue)")
            if commit {
                // TODO: s/Collection/type.name/
                self.undoManager.registerChange(
                    name: "Rename Collection",
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
