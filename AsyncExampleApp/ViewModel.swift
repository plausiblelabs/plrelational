//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import libRelational
import Binding
import BindableControls

class ViewModel {
    
    private var persons: MutableRelation
    private var selectedPersonID: MutableRelation
    private var selectedPersonName: Relation
    private var selectedPersonSales: Relation
    
    private let undoableDB: UndoableDatabase
    
    private var removals: [ObserverRemoval] = []
    
    init(undoManager: UndoManager) {
        
        func makeDB() -> (path: String, db: SQLiteDatabase) {
            let tmp = "/tmp" as NSString
            let dbname = "AsyncExampleApp.db"
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
        persons = createRelation("person", ["id", "name", "sales", "order"])
        selectedPersonID = createRelation("selected_person", ["id"])
        let selectedPerson = persons.join(selectedPersonID)
        selectedPersonName = selectedPerson.project(["name"])
        selectedPersonSales = selectedPerson.project(["sales"])
        
        undoableDB = UndoableDatabase(db: db, undoManager: undoManager)
        
        // Add some test persons
        var id: Int64 = 1
        var order: Double = 1.0
        func addPerson(name: String, _ sales: Int64) {
            let row: Row = [
                "id": RelationValue(id),
                "name": RelationValue(name),
                "sales": RelationValue(sales),
                "order": RelationValue(order)
            ]
            sqliteDB["person"]!.add(row)
            
            id += 1
            order += 1.0
        }
        addPerson("Fred", 5)
        addPerson("Wilma", 7)
        addPerson("Barney", 3)
        addPerson("Betty", 9)
        
        // Select Wilma by default
        sqliteDB["selected_person"]!.add(["id": 2])
    }
    
    deinit {
        removals.forEach{ $0() }
    }
    
    private func nameProperty(relation: Relation) -> AsyncReadWriteProperty<String> {
        return undoableDB.asyncBidiProperty(
            relation,
            action: "Rename Person",
            get: { $0.oneString },
            set: { relation.updateString($0) }
        )
    }
    
    lazy var name: AsyncReadWriteProperty<String> = self.nameProperty(self.selectedPersonName)
    
    lazy var sales: AsyncReadableProperty<String> = self.selectedPersonSales
        .signal{ $0.oneInteger }
        .map{ String($0) }
        .property
}
