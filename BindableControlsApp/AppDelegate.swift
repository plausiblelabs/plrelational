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
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    @IBOutlet weak var window: NSWindow!
    @IBOutlet var rootView: BackgroundView!
    @IBOutlet var outlineView: ExtOutlineView!
    @IBOutlet var textField: TextField!
    var checkbox: Checkbox!
    var popupButton: PopUpButton!
    var stepper: StepperView!

    var nsUndoManager: SPUndoManager!
    var listView: ListView<RowArrayElement>!

    func applicationDidFinishLaunching(aNotification: NSNotification) {
        window.delegate = self

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
        var objects = createRelation("object", ["id", "name", "editable", "color", "rocks", "parent", "order"])
        var selectedObjectID = createRelation("selected_object", ["id"])
        let selectedObjects = selectedObjectID.join(objects)
        let selectedObjectsName = selectedObjects.project(["name"])
        let selectedObjectsEditable = selectedObjects.project(["editable"])
        let selectedObjectsColor = selectedObjects.project(["color"])
        let selectedObjectsRocks = selectedObjects.project(["rocks"])
        
        // Prepare the undo manager
        nsUndoManager = SPUndoManager()
        let undoManager = UndoManager(nsmanager: nsUndoManager)
        let undoableDB = UndoableDatabase(db: db, undoManager: undoManager)

        // Add some test objects
        var id: Int64 = 1
        var order: Double = 1.0
        func addObject(name: String, editable: Bool, color: String?, rocks: Int64) {
            let colorValue: RelationValue
            if let color = color {
                colorValue = RelationValue(color)
            } else {
                colorValue = .NULL
            }
            let row: Row = [
                "id": RelationValue(id),
                "name": RelationValue(name),
                "editable": RelationValue(Int64(editable ? 1 : 0)),
                "color": colorValue,
                "rocks": RelationValue(rocks),
                "parent": .NULL,
                "order": RelationValue(order)
            ]
            objects.add(row)
            id += 1
            order += 1.0
        }
        addObject("Fred", editable: false, color: nil, rocks: 17)
        addObject("Wilma", editable: true, color: "Blue", rocks: 42)

        func nameBinding(relation: Relation) -> BidiValueBinding<String> {
            return undoableDB.bidiBinding(
                relation,
                action: "Rename Object",
                get: { $0.oneString },
                set: { relation.updateString($0) }
            )
        }
        
        func selectionBinding(relation: MutableRelation) -> BidiValueBinding<Set<RelationValue>> {
            return undoableDB.bidiBinding(
                relation,
                action: "Change Selection",
                get: { $0.allValues },
                set: { relation.replaceValues(Array($0)) }
            )
        }
        
        // Set up the list view
        let objectsArrayBinding = RelationArrayBinding(relation: objects, idAttr: "id", orderAttr: "order")
        let listViewModel = ListViewModel(
            data: objectsArrayBinding,
            contextMenu: nil,
            move: nil,
            selection: selectionBinding(selectedObjectID),
            cellIdentifier: { _ in "PageCell" },
            cellText: { row in
                let rowID = row["id"]
                let nameRelation = objects.select(Attribute("id") *== rowID).project(["name"])
                return nameBinding(nameRelation)
            },
            cellImage: nil
        )
        listView = ListView(model: listViewModel, outlineView: outlineView)
        listView.animateChanges = true

        // Add some other controls (could also do this in the xib)
        checkbox = Checkbox(frame: NSMakeRect(200, 80, 120, 24))
        checkbox.title = "Editable"
        rootView.addSubview(checkbox)

        popupButton = PopUpButton(frame: NSMakeRect(200, 120, 120, 24), pullsDown: false)
        popupButton.setAccessibilityIdentifier("Color")
        rootView.addSubview(popupButton)

        stepper = StepperView(frame: NSMakeRect(200, 160, 120, 24), min: 0, max: 999, defaultValue: 0)
        rootView.addSubview(stepper)

        // Wire up the controls and bindings
        textField.string = nameBinding(selectedObjectsName)
        textField.placeholder = selectedObjectsName.stringWhenMulti("Multiple Values")

        checkbox.checked = undoableDB.bidiBinding(
            selectedObjectsEditable,
            action: "Change Editable",
            get: { Checkbox.CheckState($0.oneBoolOrNil) },
            set: { selectedObjectsEditable.updateBoolean($0.boolValue) }
        )
        
        popupButton.titles = ValueBinding.constant(["Red", "Orange", "Yellow", "Green", "Blue", "Violet"])
        popupButton.placeholderTitle = selectedObjectsColor.stringWhenMulti("Multiple", otherwise: "Default")
        popupButton.selectedTitle = undoableDB.bidiBinding(
            selectedObjectsColor,
            action: "Change Color",
            get: { $0.oneStringOrNil },
            set: { selectedObjectsColor.updateNullableString($0) }
        )
        
        stepper.value = undoableDB.bidiBinding(
            selectedObjectsRocks,
            action: "Change Rocks",
            get: { $0.oneIntegerOrNil.map{ Int($0) } },
            set: { selectedObjectsRocks.updateInteger(Int64($0!)) }
        )
        stepper.placeholder = selectedObjectsRocks.stringWhenMulti("Multiple", otherwise: "Default")
    }
    
    func windowWillReturnUndoManager(window: NSWindow) -> NSUndoManager? {
        return nsUndoManager
    }
}
