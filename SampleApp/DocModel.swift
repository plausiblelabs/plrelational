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

    private let db: SQLiteDatabase
    let pages: SQLiteTableRelation
    private var idval: Int64 = 1
    
    init() {
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
        assert(db.createRelation("page", scheme: ["id", "name"]).ok != nil)
        
        // Prepare the default document data
        addPage("Page1")
        addPage("Page2")
        addPage("Page3")
    }
    
    func addPage(name: String) {
        pages.add(["id": RelationValue(idval), "name": RelationValue(name)])
        idval += 1
    }
}
