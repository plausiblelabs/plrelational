//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import PLRelational
import PLRelationalBinding
import PLBindableControls

enum Fruit {
    static let id = Attribute("id")
    static let name = Attribute("name")
}

enum SelectedFruit {
    static let _id = Attribute("_id")
    static let id = Attribute("id")
}

class ViewModel {
    
    struct Change {
        let snapshot: TransactionalDatabaseSnapshot
        let desc: String
    }
    
    private let db: TransactionalDatabase
    private let fruits: TransactionalRelation
    private let selectedFruitIDs: Relation
    private let selectedFruits: Relation
    private let selectedFruitName: Relation

    private let changes: [Change]
    private let changeIndex: MutableValueProperty<Int> = mutableValueProperty(0)
    
    init() {
        func makeDB() -> (path: String, db: SQLiteDatabase) {
            let tmp = "/tmp" as NSString
            let dbname = "RelationChangeApp.db"
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
        self.db = db
        fruits = createRelation("fruit", [Fruit.id, Fruit.name])
        selectedFruitIDs = createRelation("selected_fruit_id", [SelectedFruit._id, SelectedFruit.id])
        
        // Prepare higher-level relations
        selectedFruits = selectedFruitIDs.join(fruits)
        selectedFruitName = selectedFruits.project(Fruit.name)
        
        // Add some initial data directly to our stored relations
        func addFruit(_ id: Int64, _ name: String) {
            let row: Row = [
                Fruit.id: RelationValue(id),
                Fruit.name: RelationValue(name)
            ]
            _ = sqliteDB["fruit"]!.add(row)
        }
        addFruit(1, "Apple")
        addFruit(2, "Bandana")
        
        func addSelectedFruit(_ id: Int64) {
            _ = sqliteDB["selected_fruit_id"]!.add([SelectedFruit._id: 0, SelectedFruit.id: RelationValue(id)])
        }
        addSelectedFruit(1)
        
        // Build up a series of database changes, capturing a snapshot after each change
        var changes = [Change]()
        func addChange(_ desc: String) {
            // XXX: Force async changes to be applied before we snapshot
            PLRelational.Async.awaitAsyncCompletion()
            changes.append(Change(snapshot: db.takeSnapshot(), desc: desc))
        }
        
        addChange(
            "// Initial state\n" +
            "addFruit(1, \"Apple\")\n" +
            "addFruit(2, \"Bandana\")\n" +
            "addSelectedFruit(1)\n"
        )
        
        fruits.asyncAdd([Fruit.id: 3, Fruit.name: "Cheri"])
        addChange(
            "// Insert \"Cheri\"\n" +
            "fruits.asyncAdd([Fruit.id: 3, Fruit.name: \"Cheri\"])\n"
        )

        selectedFruitIDs.asyncUpdate(true, newValues: [SelectedFruit.id: 2])
        addChange(
            "// Mark \"Bandana\" as the selected fruit\n" +
            "selectedFruitIDs.asyncUpdate(true, newValues: [SelectedFruit.id: 2])\n"
        )
        
        // TODO: The goal of this step was to demonstrate performing an update and a
        // delete on the same pulse, but ArrayProperty doesn't correctly deal with that
        // yet, so for now just break it up into two separate steps
//        fruits.asyncUpdate(Fruit.id *== 3, newValues: [Fruit.name: "Cherry"])
//        fruits.asyncDelete(Fruit.id *== 1)
//        addChange(
//            "// Update \"Cherry\" and delete \"Apple\"\n" +
//            "fruits.asyncUpdate(Fruit.id *== 3, newValues: [Fruit.name: \"Cherry\"])\n" +
//            "fruits.asyncDelete(Fruit.id *== 1)\n"
//        )

        fruits.asyncUpdate(Fruit.id *== 3, newValues: [Fruit.name: "Cherry"])
        addChange(
            "// Update \"Cherry\"\n" +
            "fruits.asyncUpdate(Fruit.id *== 3, newValues: [Fruit.name: \"Cherry\"])\n"
        )
        
        fruits.asyncDelete(Fruit.id *== 1)
        addChange(
            "// Delete \"Apple\"\n" +
            "fruits.asyncDelete(Fruit.id *== 1)\n"
        )
        
        selectedFruitName.asyncUpdateString("Banana")
        addChange(
            "// Fix the name of the selected fruit (\"Banana\")\n" +
            "selectedFruitName.asyncUpdateString(\"Banana\")\n"
        )
        
        self.changes = changes
        
        // Jump back to initial state
        apply(changes.first!)
    }

    lazy var fruitsProperty: ArrayProperty<RowArrayElement> = {
        return self.fruits.arrayProperty(idAttr: Fruit.id, orderAttr: Fruit.id)
    }()

    lazy var selectedFruitIDsProperty: ArrayProperty<RowArrayElement> = {
        return self.selectedFruitIDs.arrayProperty(idAttr: SelectedFruit._id, orderAttr: SelectedFruit._id)
    }()

    lazy var selectedFruitsProperty: ArrayProperty<RowArrayElement> = {
        return self.selectedFruits.arrayProperty(idAttr: SelectedFruit._id, orderAttr: SelectedFruit._id)
    }()

    lazy var changeDescription: ReadableProperty<String> = {
        return self.changeIndex.map{ self.changes[$0].desc }
    }()
    
    lazy var previousEnabled: ReadableProperty<Bool> = {
        return self.changeIndex.map{ $0 > 0 }
    }()

    lazy var nextEnabled: ReadableProperty<Bool> = {
        return self.changeIndex.map{ $0 < self.changes.count - 1 }
    }()

    lazy var goToPreviousState: ActionProperty<()> = ActionProperty {
        let currentIndex = self.changeIndex.value
        let newIndex = currentIndex - 1
        if newIndex < 0 { return }
        self.changeIndex.change(newIndex)
        self.apply(self.changes[newIndex])
    }
    
    lazy var goToNextState: ActionProperty<()> = ActionProperty {
        let currentIndex = self.changeIndex.value
        let newIndex = currentIndex + 1
        if newIndex >= self.changes.count { return }
        self.changeIndex.change(newIndex)
        self.apply(self.changes[newIndex])
    }

    lazy var replayCurrentState: ActionProperty<()> = ActionProperty {
        // TODO
    }

    private func apply(_ change: Change) {
        db.asyncRestoreSnapshot(change.snapshot)
    }
}
