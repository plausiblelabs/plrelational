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

    var docOutlineViewModel: ListViewModel {
        let selection = ListViewModel.Selection(
            relation: selectedPage,
            // TODO: Submit a transaction that updates the selected_page relation
            set: { (id) in () },
            // TODO: Map selected_page.page_id to an index relative to ordered pages
            index: { nil }
        )

        let cell = { (relation: Relation) -> ListViewModel.Cell in
            func update(newValue: String) {
                // TODO: This is ugly
                //let searchTerms = [ComparisonTerm.EQ("id", RelationValue(Int64(1)))]
                //assert(self.pages.update(searchTerms, newValues: ["name": RelationValue(newValue)]).ok != nil)
                Swift.print("UPDATE: \(newValue)")
            }
            let text = BidiBinding(relation: relation, attribute: "name", change: Change<String>{ (newValue, oldValue, commit) in
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
        
        return ListViewModel(data: pages, selection: selection, cell: cell)
    }
}
