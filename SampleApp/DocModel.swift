//
//  DocModel.swift
//  Relational
//
//  Created by Chris Campbell on 5/2/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Foundation
import libRelational

class DocModel {

    private let undoManager: UndoManager
    private let db: SQLiteDatabase
    private let pages: OrderedBinding
    private let selectedPage: SQLiteTableRelation
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
            assert(db.createRelation(name, scheme: scheme).ok != nil)
            return db[name, scheme]
        }
        let pagesRelation = createRelation("page", ["id", "name", "order"])
        self.pages = OrderedBinding(relation: pagesRelation, idAttr: "id", orderAttr: "order")
        self.selectedPage = createRelation("selected_page", ["id", "page_id"])
        self.selectedPageItem = pagesRelation.renameAttributes(["id" : "page_id"]).join(selectedPage)
        self.db = db
        
        // Prepare the default document data
        addPage("Page1")
        addPage("Page2")
        addPage("Page3")
    }
    
    private func addPage(name: String) {
        pages.append(["id": RelationValue(pageID), "name": RelationValue(name)])
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
                self.pages.delete(RelationValue(id))
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
    
    var docOutlineViewModel: ListViewModel {
        let data = ListViewModel.Data(
            binding: pages,
            move: { (srcIndex, dstIndex) in
                // Note: dstIndex is relative to the state of the array *before* the item is removed.
                let dst = dstIndex < srcIndex ? dstIndex : dstIndex - 1
                self.undoManager.registerChange(
                    name: "Move Page",
                    perform: true,
                    forward: {
                        self.pages.move(srcIndex: srcIndex, dstIndex: dst)
                    },
                    backward: {
                        self.pages.move(srcIndex: dst, dstIndex: srcIndex)
                    }
                )
            }
        )
        
        // TODO: Selection changes/transactions should be managed in-memory
        let selection = ListViewModel.Selection(
            relation: selectedPage,
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

        let cell = { (relation: Relation) -> ListViewModel.Cell in
            func update(newValue: String) {
                // TODO: This is ugly
                //let searchTerms = [Attribute("id") *== RelationValue(Int64(1))]
                //assert(self.pages.update(searchTerms, newValues: ["name": RelationValue(newValue)]).ok != nil)
                Swift.print("UPDATE: \(newValue)")
            }
            let text = StringBidiBinding(relation: relation, attribute: "name", change: BidiChange<String>{ (newValue, oldValue, commit) in
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
            return ListViewModel.Cell(text: text)
        }
        
        return ListViewModel(data: data, selection: selection, cell: cell)
    }
    
    var itemSelected: ExistsBinding {
        return ExistsBinding(relation: selectedPageItem)
    }
    
    var itemNotSelected: NotExistsBinding {
        return NotExistsBinding(relation: selectedPageItem)
    }
    
    var selectedItemName: StringBinding {
        return StringBinding(relation: selectedPageItem, attribute: "name")
    }
}
