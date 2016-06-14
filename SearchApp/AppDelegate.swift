//
//  AppDelegate.swift
//  SearchApp
//
//  Created by Chris Campbell on 6/14/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Cocoa
import libRelational
import Binding
import BindableControls

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    @IBOutlet weak var window: NSWindow!
    @IBOutlet var outlineView: ExtOutlineView!
    @IBOutlet var textField: TextField!
    
    var nsUndoManager: SPUndoManager!
    var listView: ListView<RowArrayElement>!
    
    func applicationDidFinishLaunching(aNotification: NSNotification) {
        // By default, NSColor is set to "ignore alpha" which means that color wells
        // strip alpha, dragged-and-dropped colors lose alpha, and other assorted
        // whatever. We turn this off here, because we actually want our color wells
        // and such to work with alpha values. It's a global setting because Apple,
        // so we set it once here at app startup.
        NSColor.setIgnoresAlpha(false)
        
        window.delegate = self
        
        func makeDB() -> (path: String, db: SQLiteDatabase) {
            let tmp = NSTemporaryDirectory() as NSString
            let dbname = "SearchApp-\(NSUUID()).db"
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
        var persons = createRelation("person", ["id", "name", "sales", "order"])
        var personQuery = createRelation("person_query", ["name"])
        let personResults = personQuery.join(persons)
        var selectedPersonID = createRelation("selected_person", ["id"])

        _ = personQuery.addChangeObserver({ _ in
            Swift.print("QUERY: \(personQuery)")
            Swift.print("RESULTS: \(personResults)")
        })
        
        // Prepare the undo manager
        nsUndoManager = SPUndoManager()
        let undoManager = UndoManager(nsmanager: nsUndoManager)
        let undoableDB = UndoableDatabase(db: db, undoManager: undoManager)
        
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
            persons.add(row)
            
            id += 1
            order += 1.0
        }
        addPerson("Fred", 5)
        addPerson("Wilma", 7)
        addPerson("Barney", 3)
        addPerson("Betty", 9)
        
        func selectionBinding(relation: MutableRelation) -> MutableObservableValue<Set<RelationValue>> {
            return undoableDB.observe(
                relation,
                action: "Change Selection",
                get: { $0.allValues },
                set: { relation.replaceValues(Array($0)) }
            )
        }

        // TODO: Make these changes transient only?
        func queryBinding(relation: MutableRelation) -> MutableObservableValue<String> {
            return undoableDB.observe(
                relation,
                action: "Update Query",
                get: { $0.oneString },
                set: { relation.replaceValues([RelationValue($0)]) }
            )
        }
        
        // Set up the search text field
        textField.string = queryBinding(personQuery)
        
        // Set up the list view
        let listViewModel = ListViewModel(
            data: personResults.observableArray(),
            contextMenu: nil,
            move: nil,
            selection: selectionBinding(selectedPersonID),
            cellIdentifier: { _ in "Cell" },
            cellText: { row in
                let rowID = row["id"]
                return persons
                    .select(Attribute("id") *== rowID)
                    .project(["name"])
                    .observable{ $0.oneString }
            },
            cellImage: nil
        )
        listView = ListView(model: listViewModel, outlineView: outlineView)
    }
    
    func windowWillReturnUndoManager(window: NSWindow) -> NSUndoManager? {
        return nsUndoManager
    }
}
