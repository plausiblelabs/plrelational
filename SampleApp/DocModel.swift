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
}

class DocModel {

    private let undoManager: UndoManager
    private let db: SQLiteDatabase
    private let collections: SQLiteTableRelation
    private let orderedCollections: OrderedTreeBinding
    private let selectedCollection: SQLiteTableRelation
    private let selectedInspectorItem: SQLiteTableRelation
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
        let db = makeDB().db
        func createRelation(name: String, _ scheme: Scheme) -> SQLiteTableRelation {
            return db.getOrCreateRelation(name, scheme: scheme).ok!
        }
        self.collections = createRelation("collection", ["id", "type", "name", "parent", "order"])
        let closures = createRelation("collection_closure", ["ancestor", "descendant", "depth"])
        self.orderedCollections = OrderedTreeBinding(relation: collections, closures: closures, idAttr: "id", orderAttr: "order")
        self.selectedCollection = createRelation("selected_collection", ["id", "coll_id"])
        self.selectedInspectorItem = createRelation("selected_inspector_item", ["id", "type", "fid"])
        self.selectedCollectionItem = collections.renameAttributes(["id" : "coll_id"]).join(selectedCollection)
        self.db = db

        // Prepare the default document data
        addCollection(1, name: "Group1", type: .Group, parentID: nil)
        addCollection(2, name: "Collection1", type: .Collection, parentID: 1)
        addCollection(3, name: "Page1", type: .Page, parentID: 1)
        addCollection(4, name: "Page2", type: .Page, parentID: 1)
        addCollection(5, name: "Child1", type: .Page, parentID: 2)
        addCollection(6, name: "Child2", type: .Page, parentID: 2)
        addCollection(7, name: "Group2", type: .Group, parentID: nil)
    }
    
    private func addCollection(collectionID: Int64?, name: String, type: CollectionType, parentID: Int64?) {
        let id: Int64
        if let collectionID = collectionID {
            id = collectionID
        } else {
            id = self.collectionID
            self.collectionID += 1
        }

        let row: Row = [
            "id": RelationValue(id),
            "type": RelationValue(type.rawValue),
            "name": RelationValue(name)
        ]
        orderedCollections.add(row, parentID: parentID)
    }
    
    func newPage(name: String) {
        let id = collectionID
        undoManager.registerChange(
            name: "New Page",
            perform: true,
            forward: {
                self.addCollection(id, name: name, type: .Page, parentID: nil)
            },
            backward: {
                // TODO: Update selected_collection if needed
                self.orderedCollections.delete(RelationValue(id))
                self.collectionID -= 1
            }
        )
    }

    private func selectCollection(id: RelationValue, update: Bool) {
        if update {
            selectedCollection.update([Attribute("id") *== RelationValue(Int64(1))], newValues: ["coll_id": id])
        } else {
            selectedCollection.add(["id": RelationValue(Int64(1)), "coll_id": id])
        }
    }
    
    private func deselectCollection() {
        selectedCollection.delete([Attribute("id") *== RelationValue(Int64(1))])
    }

//    lazy var docOutlineViewModel: ListViewModel = { [unowned self] in
//        let data = ListViewModel.Data(
//            binding: self.orderedPages,
//            move: { (srcIndex, dstIndex) in
//                // Note: dstIndex is relative to the state of the array *before* the item is removed.
//                let dst = dstIndex < srcIndex ? dstIndex : dstIndex - 1
//                self.undoManager.registerChange(
//                    name: "Move Page",
//                    perform: true,
//                    forward: {
//                        self.orderedPages.move(srcIndex: srcIndex, dstIndex: dst)
//                    },
//                    backward: {
//                        self.orderedPages.move(srcIndex: dst, dstIndex: srcIndex)
//                    }
//                )
//            }
//        )
    
    lazy var docOutlineTreeViewModel: TreeViewModel = { [unowned self] in
        let data = TreeViewModel.Data(
            binding: self.orderedCollections
        )
        
        // TODO: s/Collection/Page/ depending on collection type
        let selection = TreeViewModel.Selection(
            relation: self.selectedCollection,
            set: { (id) in
                let selectedID = self.selectedCollection.rows().next().map{$0.ok!["coll_id"]}
                if let id = id {
                    self.undoManager.registerChange(
                        name: "Select Collection",
                        perform: true,
                        forward: {
                            self.selectCollection(id, update: selectedID != nil)
                        },
                        backward: {
                            if let selected = selectedID {
                                self.selectCollection(selected, update: true)
                            } else {
                                self.deselectCollection()
                            }
                        }
                    )
                } else {
                    self.undoManager.registerChange(
                        name: "Deselect Collection",
                        perform: true,
                        forward: {
                            self.deselectCollection()
                        },
                        backward: {
                            if let selected = selectedID {
                                self.selectCollection(selected, update: false)
                            }
                        }
                    )
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
            let rowRelation = self.collections.select([Attribute("id") *== rowID])
            let binding = self.collectionNameBinding(rowRelation, id: { rowID })
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
        return Int64Binding(relation: self.selectedCollectionItem, attribute: "coll_id").map{ value in
            if let value = value {
                return DocItem.Page(RelationValue(value))
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
        return self.collectionNameBinding(self.selectedCollectionItem, id: {
            return self.selectedCollectionItem.rows().next()!.ok!["coll_id"]
        })
    }()
    
    private func collectionNameBinding(relation: Relation, id: () -> RelationValue) -> StringBidiBinding {
        
        func update(newValue: String) {
            let idValue = id()
            let terms = [Attribute("id") *== idValue]
            let values: Row = ["name": RelationValue(newValue)]
            Swift.print("UPDATE: \(newValue)")
            assert(self.collections.update(terms, newValues: values).ok != nil)
        }
        
        return StringBidiBinding(relation: relation, attribute: "name", change: BidiChange<String>{ (newValue, oldValue, commit) in
            Swift.print("\(commit ? "COMMIT" : "CHANGE") new=\(newValue) old=\(oldValue)")
            if commit {
                // TODO: s/Collection/Page/ depending on collection type
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
