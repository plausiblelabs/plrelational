//
//  AppDelegate.swift
//  BindableControlsApp
//
//  Created by Chris Campbell on 5/31/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Cocoa
import libRelational
import Binding

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet weak var window: NSWindow!
    @IBOutlet var rootView: BackgroundView!
    @IBOutlet var textField: TextField!
    var checkbox: Checkbox!

    func applicationDidFinishLaunching(aNotification: NSNotification) {

        func makeDB() -> (path: String, db: SQLiteDatabase) {
            let tmp = NSTemporaryDirectory() as NSString
            let dbname = "testing-\(NSUUID()).db"
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
        var objects = createRelation("object", ["id", "name", "editable"])
        let firstObject = objects.select(Attribute("id") *== 1)
        let firstObjectName = firstObject.project(["name"])
        let firstObjectEditable = firstObject.project(["editable"])
        
        // Prepare the undo manager
        let nsmanager = SPUndoManager()
        //self.undoManager = nsmanager
        let undoManager = UndoManager(nsmanager: nsmanager)
        let undoableDB = UndoableDatabase(db: db, undoManager: undoManager)

        // Add a test object
        objects.add(["id": 1, "name": "Fred", "editable": 0])

        // Add some other controls (could also do this in the xib)
        checkbox = Checkbox(frame: NSMakeRect(30, 100, 120, 24), checkState: false)
        checkbox.title = "Checkbox"
        rootView.addSubview(checkbox)

        // Wire up the controls and bindings
        textField.string = undoableDB.bidiBinding(
            firstObjectName,
            action: "Rename Object",
            get: { $0.oneString },
            set: { firstObjectName.updateString($0) }
        )

        checkbox.checked = undoableDB.bidiBinding(
            firstObjectEditable,
            action: "Change Editable",
            get: { Checkbox.CheckState($0.oneBool) },
            set: { firstObjectEditable.updateBoolean($0.boolValue) }
        )
    }
}
