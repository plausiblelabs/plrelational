//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Cocoa
import PLRelational
import PLRelationalBinding
import PLBindableControls

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    @IBOutlet weak var window: NSWindow!
    @IBOutlet var rootView: BackgroundView!
    @IBOutlet var outlineView: ExtOutlineView!
    private var textField: TextField!
    private var checkbox: Checkbox!
    private var popupButton: PopUpButton<String>!
    private var stepper: StepperView!
    private var comboBox: ComboBox<String>!
    private var colorPicker: ColorPickerView!

    private var nsUndoManager: SPUndoManager!
    private var listView: ListView<RowArrayElement>!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // By default, NSColor is set to "ignore alpha" which means that color wells
        // strip alpha, dragged-and-dropped colors lose alpha, and other assorted
        // whatever. We turn this off here, because we actually want our color wells
        // and such to work with alpha values. It's a global setting because Apple,
        // so we set it once here at app startup.
        NSColor.ignoresAlpha = false
        
        window.delegate = self

        func makeDB() -> (path: String, db: SQLiteDatabase) {
            let tmp = NSTemporaryDirectory() as NSString
            let dbname = "testing-\(UUID()).db"
            let path = tmp.appendingPathComponent(dbname)
            _ = try? FileManager.default.removeItem(atPath: path)
            
            let db = try! SQLiteDatabase(path)
            
            return (path, db)
        }
        
        // Prepare the stored relations
        let sqliteDB = makeDB().db
        let db = TransactionalDatabase(sqliteDB)
        func createRelation(_ name: String, _ scheme: Scheme) -> TransactionalRelation {
            let createResult = sqliteDB.createRelation(name, scheme: scheme)
            precondition(createResult.ok != nil)
            return db[name]
        }
        var persons = createRelation("person", ["id", "name", "friendly", "best_friend", "fav_day", "fav_color", "rocks", "parent", "order"])
        var selectedPersonID = createRelation("selected_person", ["id"])
        let selectedPersons = selectedPersonID.join(persons)
        let selectedPersonsName = selectedPersons.project(["name"])
        let selectedPersonsFriendly = selectedPersons.project(["friendly"])
        let selectedPersonsFriend = selectedPersons.project(["best_friend"])
        let selectedPersonsDay = selectedPersons.project(["fav_day"])
        let selectedPersonsColor = selectedPersons.project(["fav_color"])
        let selectedPersonsRocks = selectedPersons.project(["rocks"])
        
        // Prepare the undo manager
        nsUndoManager = SPUndoManager()
        let undoManager = UndoManager(nsmanager: nsUndoManager)
        let undoableDB = UndoableDatabase(db: db, undoManager: undoManager)

        // Add some test persons
        var id: Int64 = 1
        var order: Double = 1.0
        func addPerson(_ name: String, friendly: Bool, day: String?, color: Color?, rocks: Int64) {
            let dayValue: RelationValue
            if let day = day {
                dayValue = RelationValue(day)
            } else {
                dayValue = .null
            }
            
            let colorValue: RelationValue
            if let color = color {
                colorValue = RelationValue(color.stringValue)
            } else {
                colorValue = .null
            }
            
            let row: Row = [
                "id": RelationValue(id),
                "name": RelationValue(name),
                "friendly": RelationValue(Int64(friendly ? 1 : 0)),
                "best_friend": .null,
                "fav_day": dayValue,
                "fav_color": colorValue,
                "rocks": RelationValue(rocks),
                "parent": .null,
                "order": RelationValue(order)
            ]
            _  = persons.add(row)
            
            id += 1
            order += 1.0
        }
        addPerson("Fred", friendly: false, day: nil, color: nil, rocks: 17)
        addPerson("Wilma", friendly: true, day: "Friday", color: Color.blue, rocks: 42)

        func nameProperty(_ relation: Relation, initialValue: String?) -> AsyncReadWriteProperty<String> {
            return undoableDB.bidiProperty(
                action: "Rename Person",
                signal: relation.oneString(initialValue: initialValue),
                update: {
                    relation.asyncUpdateString($0)
                }
            )
        }
        
        func listSelectionProperty(_ relation: TransactionalRelation) -> AsyncReadWriteProperty<Set<RelationValue>> {
            return undoableDB.bidiProperty(
                action: "Change Selection",
                signal: relation.allRelationValues(),
                update: { relation.asyncReplaceValues(Array($0)) }
            )
        }
        
        // Set up the list view
        let listViewModel = ListViewModel(
            data: persons.arrayProperty(idAttr: "id", orderAttr: "order"),
            contextMenu: nil,
            move: nil,
            cellIdentifier: { _ in "PageCell" },
            cellText: { row in
                let rowID = row["id"]
                let initialValue: String? = row["name"].get()
                let nameRelation = persons.select(Attribute("id") *== rowID).project(["name"])
                return .asyncReadWrite(nameProperty(nameRelation, initialValue: initialValue))
            },
            cellImage: nil
        )
        listView = ListView(model: listViewModel, outlineView: outlineView)
        listView.animateChanges = true
        listView.selection <~> listSelectionProperty(selectedPersonID)

        // Add some other controls (could also do this in the xib)
        textField = TextField(frame: NSMakeRect(200, 30, 200, 24))
        textField.setAccessibilityIdentifier("NameField")
        rootView.addSubview(textField)
        
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
        colorPicker.frame = NSMakeRect(200, 240, 240, 24)
        rootView.addSubview(colorPicker)
        
        // Set up the bindings between controls and view model
        textField.deliverTransientChanges = true
        textField.string <~> nameProperty(selectedPersonsName, initialValue: nil)
        //textField.placeholder <~ selectedPersonsName.stringWhenMulti("Multiple Values")

        // TODO: Disable or clear when nothing selected
        checkbox.checkState <~> undoableDB.bidiProperty(
            action: "Change Friendly",
            signal: selectedPersonsFriendly.oneBoolOrNil().map{ CheckState($0) },
            update: { selectedPersonsFriendly.asyncUpdateBoolean($0.boolValue) }
        )
        
        let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let popupItems = days.map{ titledMenuItem($0) }
        popupButton.items <~ constantValueProperty(popupItems)
        //popupButton.defaultItemContent = MenuItemContent(object: "Default", title: selectedPersonsColor.stringWhenMulti("Multiple", otherwise: "Default"))
        popupButton.selectedObject <~> undoableDB.bidiProperty(
            action: "Change Favorite Day",
            signal: selectedPersonsDay.oneStringOrNil(),
            update: { selectedPersonsDay.asyncUpdateNullableString($0) }
        )

        stepper.value <~> undoableDB.bidiProperty(
            action: "Change Rocks",
            signal: selectedPersonsRocks.oneIntegerOrNil().map{ $0.map{ Int($0) } },
            update: { selectedPersonsRocks.asyncUpdateInteger(Int64($0!)) }
        )
        //stepper.placeholder <~ selectedPersonsRocks.stringWhenMulti("Multiple", otherwise: "Default")

        comboBox.items <~ constantValueProperty(["Alice", "Bob", "Carlos"])
        comboBox.value <~> undoableDB.bidiProperty(
            action: "Change Best Friend",
            signal: selectedPersonsFriend.oneStringOrNil(),
            update: { selectedPersonsFriend.asyncUpdateNullableString($0) }
        )
        //comboBox.placeholder <~ selectedPersonsFriend.stringWhenMulti("Multiple", otherwise: "Default")

        colorPicker.color <~> undoableDB.bidiProperty(
            action: "Change Favorite Color",
            signal: selectedPersonsColor.commonValue{ rv -> Color? in
                if let s: String = rv.get() {
                    return Color(string: s)
                } else {
                    return nil
                }
            },
            update: { (commonValue: CommonValue<Color>) in
                guard let color = commonValue.orNil() else { preconditionFailure("Expected a single color value") }
                selectedPersonsColor.asyncUpdateString(color.stringValue)
            }
        )
    }
    
    func windowWillReturnUndoManager(_ window: NSWindow) -> Foundation.UndoManager? {
        return nsUndoManager
    }
}
