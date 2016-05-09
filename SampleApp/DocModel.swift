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

class DocModel {

    private let undoManager: UndoManager
    private let db: SQLiteDatabase
    private let pages: SQLiteTableRelation
    private let orderedPages: OrderedBinding
    private let selectedPage: SQLiteTableRelation
    private let selectedInspectorItem: SQLiteTableRelation
    private let selectedPageItem: Relation
    private var pageID: Int64 = 1
    
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
        self.pages = createRelation("page", ["id", "name", "order"])
        self.orderedPages = OrderedBinding(relation: pages, idAttr: "id", orderAttr: "order")
        self.selectedPage = createRelation("selected_page", ["id", "page_id"])
        self.selectedInspectorItem = createRelation("selected_inspector_item", ["id", "type", "fid"])
        self.selectedPageItem = pages.renameAttributes(["id" : "page_id"]).join(selectedPage)
        self.db = db
        
        // XXX
        //let collections = createRelation("collection", ["id", "type", "name", "parent", "order"])
        //let closures = createRelation("collection_closure", ["ancestor", "descendant", "depth"])
        //let orderedCollections = OrderedTreeBinding(relation: collections, closures: closures, idAttr: "id", orderAttr: "order")
        
        // Prepare the default document data
        addPage("Page1")
        addPage("Page2")
        addPage("Page3")
    }
    
    private func addPage(name: String) {
        orderedPages.append(["id": RelationValue(pageID), "name": RelationValue(name)])
        pageID += 1
    }
    
    func newPage(name: String) {
        let id = pageID
        undoManager.registerChange(
            name: "New Page",
            perform: true,
            forward: {
                self.addPage(name)
            },
            backward: {
                // TODO: Update selected_page if needed
                self.orderedPages.delete(RelationValue(id))
                self.pageID -= 1
            }
        )
    }

    private func selectPage(id: RelationValue, update: Bool) {
        if update {
            selectedPage.update([Attribute("id") *== RelationValue(Int64(1))], newValues: ["page_id": id])
        } else {
            selectedPage.add(["id": RelationValue(Int64(1)), "page_id": id])
        }
    }
    
    private func deselectPage() {
        selectedPage.delete([Attribute("id") *== RelationValue(Int64(1))])
    }

    lazy var docOutlineViewModel: ListViewModel = { [unowned self] in
        let data = ListViewModel.Data(
            binding: self.orderedPages,
            move: { (srcIndex, dstIndex) in
                // Note: dstIndex is relative to the state of the array *before* the item is removed.
                let dst = dstIndex < srcIndex ? dstIndex : dstIndex - 1
                self.undoManager.registerChange(
                    name: "Move Page",
                    perform: true,
                    forward: {
                        self.orderedPages.move(srcIndex: srcIndex, dstIndex: dst)
                    },
                    backward: {
                        self.orderedPages.move(srcIndex: dst, dstIndex: srcIndex)
                    }
                )
            }
        )
        
        // TODO: Selection changes/transactions should be managed in-memory
        let selection = ListViewModel.Selection(
            relation: self.selectedPage,
            set: { (id) in
                let selectedID = self.selectedPage.rows().next().map{$0.ok!["page_id"]}
                if let id = id {
                    self.undoManager.registerChange(
                        name: "Select Page",
                        perform: true,
                        forward: {
                            self.selectPage(id, update: selectedID != nil)
                        },
                        backward: {
                            if let selected = selectedID {
                                self.selectPage(selected, update: true)
                            } else {
                                self.deselectPage()
                            }
                        }
                    )
                } else {
                    self.undoManager.registerChange(
                        name: "Deselect Page",
                        perform: true,
                        forward: {
                            self.deselectPage()
                        },
                        backward: {
                            if let selected = selectedID {
                                self.selectPage(selected, update: false)
                            }
                        }
                    )
                }
            },
            get: {
                return self.selectedPage.rows().next().map{$0.ok!["page_id"]}
            }
        )

        let cell = { (row: Row) -> ListViewModel.Cell in
            // TODO: Ideally we'd have a way to create a projection Relation directly from
            // an existing Row.  In the meantime, we'll select/project from the original
            // relation.  The downside of that latter approach is that the cell text will
            // disappear before the cell fades out in the case where the item is deleted.
            // (If the cell was bound to a projection of the row, presumably it would
            // continue to work even after the row has been deleted from the underlying
            // relation.)
            let rowID = row["id"]
            let rowRelation = self.pages.select([Attribute("id") *== rowID])
            let binding = self.pageNameBinding(rowRelation, id: { rowID })
            return ListViewModel.Cell(text: binding)
        }
        
        return ListViewModel(data: data, selection: selection, cell: cell)
    }()
    
    lazy var itemSelected: ExistsBinding = { [unowned self] in
        return ExistsBinding(relation: self.selectedPageItem)
    }()
    
    lazy var itemNotSelected: NotExistsBinding = { [unowned self] in
        return NotExistsBinding(relation: self.selectedPageItem)
    }()

    private lazy var selectedPageDocItem: ValueBinding<DocItem?> = { [unowned self] in
        return Int64Binding(relation: self.selectedPageItem, attribute: "page_id").map{ value in
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
        return self.selectedPageDocItem.zip(self.selectedInspectorDocItem).map{ (docItem, inspectorItem) in
            return inspectorItem ?? docItem
        }
    }()
    
    lazy var selectedItemType: ValueBinding<String?> = { [unowned self] in
        return self.selectedDocItem.map{ $0?.typeName }
    }()
    
    lazy var selectedItemName: StringBidiBinding = { [unowned self] in
        return self.pageNameBinding(self.selectedPageItem, id: {
            return self.selectedPageItem.rows().next()!.ok!["page_id"]
        })
    }()
    
    private func pageNameBinding(relation: Relation, id: () -> RelationValue) -> StringBidiBinding {

        func update(newValue: String) {
            // TODO: If we had writable views, and assuming the given Relation represents
            // a single value, we should be able to update that relation rather than updating
            // the original relation (in which case we would no longer need the hack that passes
            // in a closure that returns the ID of the page whose name will be updated)
            let idValue = id()
            let terms = [Attribute("id") *== idValue]
            let values: Row = ["name": RelationValue(newValue)]
            Swift.print("UPDATE: \(newValue)")
            assert(self.pages.update(terms, newValues: values).ok != nil)
        }
        
        return StringBidiBinding(relation: relation, attribute: "name", change: BidiChange<String>{ (newValue, oldValue, commit) in
            Swift.print("\(commit ? "COMMIT" : "CHANGE") new=\(newValue) old=\(oldValue)")
            if commit {
                self.undoManager.registerChange(
                    name: "Rename Page",
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
