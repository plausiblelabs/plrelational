//
//  Document.swift
//  RichText
//
//  Created by Chris Campbell on 6/2/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Cocoa
import PLRelational
import Binding
import BindableControls

class Document: NSDocument {

    @IBOutlet var textField: TextField!
    @IBOutlet var button: NSButton!

    private var db: SQLiteDatabase!
    
    private var collections: MutableRelation
//    private var selectedCollectionID: MutableRelation
//    private let inspectorItems: Relation
//    private let selectedCollection: Relation

    override init() {
        
        func makeDB() -> (path: String, db: SQLiteDatabase) {
            let tmp = NSTemporaryDirectory() as NSString
            let dbname = "testing-\(NSUUID()).db"
            let path = tmp.stringByAppendingPathComponent(dbname)
            _ = try? NSFileManager.defaultManager().removeItemAtPath(path)
            
            let db = try! SQLiteDatabase(path)
            
            return (path, db)
        }
        
        let sqliteDB = makeDB().db
        
        func createRelation(name: String, _ scheme: Scheme) -> MutableRelation {
            let createResult = sqliteDB.createRelation(name, scheme: scheme)
            precondition(createResult.ok != nil)
            return sqliteDB[name]!
        }
        self.collections = createRelation("collection", ["id", "name", "parent", "order"])
//        self.selectedCollectionID = createRelation("selected_collection", ["coll_id"])
//        
//        self.selectedCollection = selectedCollectionID
//            .equijoin(collections, matching: ["coll_id": "id"])
//            .project(["id", "name"])
//        
//        self.inspectorItems = selectedCollection
//            .join(MakeRelation(["parent", "order"], [.NULL, 5.0]))
        
        super.init()
        
        addDefaultData()
    }
    
    func addDefaultData() {
        addCollection(1, name: "Group1", order: 1.0)
        addCollection(2, name: "Group2", order: 2.0)
    }
    
    private func addCollection(collectionID: Int64, name: String, order: Double) {
        let row: Row = [
            "id": RelationValue(collectionID),
            "name": RelationValue(name),
            "parent": .NULL,
            "order": RelationValue(order)
        ]
        self.collections.add(row)
    }

    override class func autosavesInPlace() -> Bool {
        return false
    }

    override var windowNibName: String? {
        return "Document"
    }

    override func dataOfType(typeName: String) throws -> NSData {
        throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: nil)
    }

    override func readFromData(data: NSData, ofType typeName: String) throws {
        throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: nil)
    }
    
    override func windowControllerDidLoadNib(aController: NSWindowController) {
        super.windowControllerDidLoadNib(aController)
    }
    
    var first = true
    
    @IBAction func buttonClicked(sender: NSButton) {
        let rowID: RelationValue = first ? 1 : 2
        first = !first
        
        let selectedItemName = collections.select(Attribute("id") *== rowID).project(["name"])
        //let nameProperty = selectedItemName.property{ $0.oneString }
        //Swift.print("NAME: \(nameProperty.value)")
        
        let removal = selectedItemName.addChangeObserver({ _ in
            Swift.print("CHANGED")
        })
        Swift.print("NAME: \(selectedItemName)")
        removal()
        
//        textField.string.unbindAll()
//        textField.string <~> nameProperty
    }
}
