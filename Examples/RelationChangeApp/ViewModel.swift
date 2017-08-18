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
    static let fruitID = Attribute("fruit_id")
}

private let normalStepDuration: TimeInterval = 1.0
private let fastStepDuration: TimeInterval = 0.1

class ViewModel {
    
    struct State {
        let before: TransactionalDatabaseSnapshot
        let after: TransactionalDatabaseSnapshot
        let desc: String
    }
    
    struct Animation {
        let stepDuration: TimeInterval
        let snapshot: TransactionalDatabaseSnapshot
    }
    
    private let db: TransactionalDatabase
    private let fruits: TransactionalRelation
    private let selectedFruitIDs: TransactionalRelation
    private let selectedFruits: Relation
    private let selectedFruitName: Relation

    private var states: [State] = []
    let stateIndex: MutableValueProperty<Int> = mutableValueProperty(0)
    private var lastPlayedIndex: MutableValueProperty<Int> = mutableValueProperty(-1)
    let animating: MutableValueProperty<Bool> = mutableValueProperty(false)
    private var animations: [Animation] = []
    
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
        selectedFruitIDs = createRelation("selected_fruit_id", [SelectedFruit._id, SelectedFruit.fruitID])
        
        // Prepare higher-level relations
        selectedFruits = fruits.equijoin(selectedFruitIDs, matching: [Fruit.id: SelectedFruit.fruitID])
        selectedFruitName = selectedFruits.project(Fruit.name)
        
        // Build up a series of database states, capturing a snapshot before and after each change
        func addState(_ desc: String, _ changes: (() -> Void)) {
            let before = db.takeSnapshot()
            changes()
            // XXX: Force async changes to be applied before we take "after" snapshot
            PLRelational.Async.awaitAsyncCompletion()
            let after = db.takeSnapshot()
            states.append(State(before: before, after: after, desc: desc))
        }

        addState(
            "// Step 1: Populate the empty relations\n" +
            "fruits.asyncAdd([Fruit.id: 1, Fruit.name: \"Apple\"])\n" +
            "fruits.asyncAdd([Fruit.id: 2, Fruit.name: \"Bandana\"])\n" +
            "selectedFruitIDs.asyncAdd([SelectedFruit._id: 0, SelectedFruit.fruitID: 1])",
            {
                fruits.asyncAdd([Fruit.id: 1, Fruit.name: "Apple"])
                fruits.asyncAdd([Fruit.id: 2, Fruit.name: "Bandana"])
                selectedFruitIDs.asyncAdd([SelectedFruit._id: 0, SelectedFruit.fruitID: 1])
            }
        )
        
        addState(
            "// Step 2: Insert \"Cheri\"\n" +
            "fruits.asyncAdd([Fruit.id: 3, Fruit.name: \"Cheri\"])",
            {
                fruits.asyncAdd([Fruit.id: 3, Fruit.name: "Cheri"])
            }
        )

        addState(
            "// Step 3: Mark \"Bandana\" as the selected fruit\n" +
            "selectedFruitIDs.asyncUpdate(true, newValues: [SelectedFruit.id: 2])",
            {
                selectedFruitIDs.asyncUpdate(true, newValues: [SelectedFruit.fruitID: 2])
            }
        )
        
        addState(
            "// Step 4: Fix spelling of \"Cherry\" by updating the source relation\n" +
            "fruits.asyncUpdate(Fruit.id *== 3, newValues: [Fruit.name: \"Cherry\"])",
            {
                fruits.asyncUpdate(Fruit.id *== 3, newValues: [Fruit.name: "Cherry"])
            }
        )
        
        addState(
            "// Step 5: Delete \"Apple\"\n" +
            "fruits.asyncDelete(Fruit.id *== 1)",
            {
                fruits.asyncDelete(Fruit.id *== 1)
            }
        )
        
        addState(
            "// Step 6: Fix spelling of the selected fruit (\"Banana\") by applying\n" +
            "// the update to the higher-level relation (will automatically propagate\n" +
            "// back to the source relation)\n" +
            "selectedFruitName.asyncUpdateString(\"Banana\")",
            {
                selectedFruitName.asyncUpdateString("Banana")
            }
        )
        
        // Jump back to initial state
        self.db.asyncRestoreSnapshot(states.first!.before)
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

    lazy var stateDescriptions: [String] = {
        return self.states.map{ $0.desc }
    }()

    lazy var resetVisible: ReadableProperty<Bool> = {
        return zip(self.stateIndex, self.lastPlayedIndex).map{ (current, played) in current == self.states.count - 1 && played == current }
    }()
    
    lazy var nextVisible: ReadableProperty<Bool> = {
        return not(self.resetVisible)
    }()
    
    lazy var replayEnabled: ReadableProperty<Bool> = {
        return not(self.animating) *&& (self.stateIndex *== self.lastPlayedIndex)
    }()

    lazy var nextButtonTitle: ReadableProperty<String> = {
        return self.replayEnabled.map{ $0 ? "Next Step" : "Play Step" }
    }()
    
    lazy var goToNextState: ActionProperty<()> = ActionProperty {
        let currentStateIndex = self.stateIndex.value
        let currentPlayedIndex = self.lastPlayedIndex.value
        if currentPlayedIndex < currentStateIndex {
            // Play the current state
            self.lastPlayedIndex.change(currentStateIndex)
            self.performAnimations([
                self.animation(fast: false, snapshot: self.states[currentStateIndex].after)
            ])
        } else {
            // Go forward to the next state
            let newStateIndex = currentStateIndex + 1
            if newStateIndex >= self.states.count { return }
            self.stateIndex.change(newStateIndex)
        }
    }

    lazy var goToInitialState: ActionProperty<()> = ActionProperty {
        self.lastPlayedIndex.change(-1)
        self.stateIndex.change(0)
        self.performAnimations([
            self.animation(fast: true, snapshot: self.states.first!.before)
        ])
    }

    lazy var replayCurrentState: ActionProperty<()> = ActionProperty {
        let state = self.states[self.stateIndex.value]
        self.performAnimations([
            self.animation(fast: true, snapshot: state.before),
            self.animation(fast: false, snapshot: state.after)
        ])
    }

    private func animation(fast: Bool, snapshot: TransactionalDatabaseSnapshot) -> Animation {
        return Animation(stepDuration: fast ? fastStepDuration : normalStepDuration, snapshot: snapshot)
    }
    
    private func performAnimations(_ animations: [Animation]) {
        self.animations = animations
        self.performPendingAnimation()
    }
    
    private func performPendingAnimation() {
        if let animation = animations.first {
            // Perform the animation
            if !animating.value {
                animating.change(true)
            }
            db.asyncRestoreSnapshot(animation.snapshot)
        } else {
            // No more animations to perform
            animating.change(false)
        }
    }

    func prepareNextAnimation() {
        animations.removeFirst()
        performPendingAnimation()
    }
    
    var currentStepDuration: TimeInterval {
        return animations.first!.stepDuration
    }
}
