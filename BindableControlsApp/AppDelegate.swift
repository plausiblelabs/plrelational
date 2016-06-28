//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import libRelational
import Binding
import BindableControls

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    @IBOutlet weak var window: NSWindow!
    @IBOutlet var rootView: BackgroundView!
    @IBOutlet var outlineView: ExtOutlineView!
    @IBOutlet var textField: TextField!
    var checkbox: Checkbox!
    var popupButton: PopUpButton<String>!
    var stepper: StepperView!
    var comboBox: ComboBox<String>!
    var colorPicker: ColorPickerView!

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
        var objects = createRelation("object", ["id", "name", "editable", "best_friend", "fav_day", "fav_color", "rocks", "parent", "order"])
        var selectedObjectID = createRelation("selected_object", ["id"])
        let selectedObjects = selectedObjectID.join(objects)
        let selectedObjectsName = selectedObjects.project(["name"])
        let selectedObjectsEditable = selectedObjects.project(["editable"])
        let selectedObjectsFriend = selectedObjects.project(["best_friend"])
        let selectedObjectsDay = selectedObjects.project(["fav_day"])
        let selectedObjectsColor = selectedObjects.project(["fav_color"])
        let selectedObjectsRocks = selectedObjects.project(["rocks"])
        
        // Prepare the undo manager
        nsUndoManager = SPUndoManager()
        let undoManager = UndoManager(nsmanager: nsUndoManager)
        let undoableDB = UndoableDatabase(db: db, undoManager: undoManager)

        // Add some test objects
        var id: Int64 = 1
        var order: Double = 1.0
        func addObject(name: String, editable: Bool, day: String?, color: Color?, rocks: Int64) {
            let dayValue: RelationValue
            if let day = day {
                dayValue = RelationValue(day)
            } else {
                dayValue = .NULL
            }
            
            let colorValue: RelationValue
            if let color = color {
                colorValue = RelationValue(color.stringValue)
            } else {
                colorValue = .NULL
            }
            
            let row: Row = [
                "id": RelationValue(id),
                "name": RelationValue(name),
                "editable": RelationValue(Int64(editable ? 1 : 0)),
                "best_friend": .NULL,
                "fav_day": dayValue,
                "fav_color": colorValue,
                "rocks": RelationValue(rocks),
                "parent": .NULL,
                "order": RelationValue(order)
            ]
            objects.add(row)
            
            id += 1
            order += 1.0
        }
        addObject("Fred", editable: false, day: nil, color: nil, rocks: 17)
        addObject("Wilma", editable: true, day: "Friday", color: Color.blue, rocks: 42)

        func nameProperty(relation: Relation) -> ReadWriteProperty<String> {
            return undoableDB.bidiProperty(
                relation,
                action: "Rename Object",
                get: { $0.oneString },
                set: { relation.updateString($0) }
            )
        }
        
        func listSelectionProperty(relation: MutableRelation) -> ReadWriteProperty<Set<RelationValue>> {
            return undoableDB.bidiProperty(
                relation,
                action: "Change Selection",
                get: { $0.allValues },
                set: { relation.replaceValues(Array($0)) }
            )
        }
        
        // Set up the list view
        let listViewModel = ListViewModel(
            data: objects.arrayProperty(),
            contextMenu: nil,
            move: nil,
            selection: listSelectionProperty(selectedObjectID),
            cellIdentifier: { _ in "PageCell" },
            cellText: { row in
                let rowID = row["id"]
                let nameRelation = objects.select(Attribute("id") *== rowID).project(["name"])
                return .ReadWrite(nameProperty(nameRelation))
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
        popupButton.setAccessibilityIdentifier("Day")
        rootView.addSubview(popupButton)

        stepper = StepperView(frame: NSMakeRect(200, 160, 120, 24), min: 0, max: 999, defaultValue: 0)
        rootView.addSubview(stepper)

        comboBox = ComboBox(frame: NSMakeRect(200, 200, 120, 24))
        rootView.addSubview(comboBox)
        
        colorPicker = ColorPickerView(defaultColor: Color.white)
        colorPicker.frame = NSMakeRect(200, 240, 200, 24)
        rootView.addSubview(colorPicker)
            
        // Set up the bindings between controls and view model
        textField.string <~> nameProperty(selectedObjectsName)
        textField.placeholder <~ selectedObjectsName.stringWhenMulti("Multiple Values")

        checkbox.checked <~> undoableDB.bidiProperty(
            selectedObjectsEditable,
            action: "Change Editable",
            get: { CheckState($0.oneBoolOrNil) },
            set: { selectedObjectsEditable.updateBoolean($0.boolValue) }
        )
        
        let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let popupItems = days.map{ titledMenuItem($0) }
        popupButton.items <~ constantValueProperty(popupItems)
        popupButton.defaultItemContent = MenuItemContent(object: "Default", title: selectedObjectsColor.stringWhenMulti("Multiple", otherwise: "Default"))
        popupButton.selectedObject <~> undoableDB.bidiProperty(
            selectedObjectsDay,
            action: "Change Favorite Day",
            get: { $0.oneStringOrNil },
            set: { selectedObjectsDay.updateNullableString($0) }
        )
        
        stepper.value <~> undoableDB.bidiProperty(
            selectedObjectsRocks,
            action: "Change Rocks",
            get: { $0.oneIntegerOrNil.map{ Int($0) } },
            set: { selectedObjectsRocks.updateInteger(Int64($0!)) }
        )
        stepper.placeholder <~ selectedObjectsRocks.stringWhenMulti("Multiple", otherwise: "Default")
        
        comboBox.items <~ constantValueProperty(["Alice", "Bob", "Carlos"])
        comboBox.value <~> undoableDB.bidiProperty(
            selectedObjectsFriend,
            action: "Change Best Friend",
            get: { $0.oneStringOrNil },
            set: { selectedObjectsFriend.updateNullableString($0) }
        )
        comboBox.placeholder <~ selectedObjectsFriend.stringWhenMulti("Multiple", otherwise: "Default")
        
        colorPicker.color <~> undoableDB.bidiProperty(
            selectedObjectsColor,
            action: "Change Favorite Color",
            get: {
                $0.commonValue{ rv -> Color? in
                    if let s: String = rv.get() {
                        return Color(string: s)
                    } else {
                        return nil
                    }
                }
            },
            set: { (commonValue: CommonValue<Color>) in
                guard let color = commonValue.orNil() else { preconditionFailure("Expected a single color value") }
                selectedObjectsColor.updateString(color.stringValue)
            }
        )
    }
    
    func windowWillReturnUndoManager(window: NSWindow) -> NSUndoManager? {
        return nsUndoManager
    }
}
