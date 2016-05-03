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
    let pages: SQLiteTableRelation
    let selectedPage: SQLiteTableRelation
    
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
        db = makeDB().db
        pages = db["page", ["id", "name"]]
        selectedPage = db["selected_page", ["id", "page_id"]]
        assert(db.createRelation("page", scheme: ["id", "name"]).ok != nil)
        assert(db.createRelation("selected_page", scheme: ["id", "page_id"]).ok != nil)
        
        // Prepare the default document data
        addPage("Page1")
        addPage("Page2")
        addPage("Page3")
    }
    
    func addPage(name: String) {
        pages.add(["id": RelationValue(pageID), "name": RelationValue(name)])
        pageID += 1
    }
}
