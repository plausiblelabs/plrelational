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
    
    private let fruitsChangesText: MutableValueProperty<String> = mutableValueProperty("")
    private let selectedFruitIDsChangesText: MutableValueProperty<String> = mutableValueProperty("")
    private let selectedFruitsChangesText: MutableValueProperty<String> = mutableValueProperty("")
    
    private var observerRemovals: [ObserverRemoval] = []

    init() {
        // Prepare the stored relations
        let memoryDB = MemoryTableDatabase()
        let db = TransactionalDatabase(memoryDB)
        func createRelation(_ name: String, _ scheme: Scheme) -> TransactionalRelation {
            _ = memoryDB.createRelation(name, scheme: scheme)
            return db[name]
        }
        
        // Each item in the `fruits` relation will have a unique identifier and a
        // (possibly misspelled) name
        fruits = createRelation(
            "fruit",
            [Fruit.id, Fruit.name])
        
        // The `fruit_id` attribute in the `selectedFruitsIDs` relation acts as a
        // foreign key, referring to a row from the `fruits` relation
        selectedFruitIDs = createRelation(
            "selected_fruit_id",
            [SelectedFruit._id, SelectedFruit.fruitID])
        
        // Join `fruits` with `selectedFruitIDs` to produce a new Relation that will
        // contain our fruit(s) of interest.  (In a real application we might use this
        // setup to model the selection state for a list view, for example.)
        selectedFruits = fruits.equijoin(selectedFruitIDs,
                                         matching: [Fruit.id: SelectedFruit.fruitID])
        
        // Project just the `name` Attribute to produce another Relation that will
        // contain only a single string value (the selected fruit's name)
        selectedFruitName = selectedFruits.project(Fruit.name)
        
        // Build up a series of database states, capturing a snapshot before and after each change
        self.db = db
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
            "fruits.asyncAdd([Fruit.id: 2, Fruit.name: \"Apricot\"])\n" +
            "fruits.asyncAdd([Fruit.id: 3, Fruit.name: \"Bandana\"])\n" +
            "selectedFruitIDs.asyncAdd([SelectedFruit._id: 0, SelectedFruit.fruitID: 1])",
            {
                fruits.asyncAdd([Fruit.id: 1, Fruit.name: "Apple"])
                fruits.asyncAdd([Fruit.id: 2, Fruit.name: "Apricot"])
                fruits.asyncAdd([Fruit.id: 3, Fruit.name: "Bandana"])
                selectedFruitIDs.asyncAdd([SelectedFruit._id: 0, SelectedFruit.fruitID: 1])
            }
        )

        addState(
            "// Step 2: Delete \"Apricot\"\n" +
            "fruits.asyncDelete(Fruit.id *== 2)",
            {
                fruits.asyncDelete(Fruit.id *== 2)
            }
        )

        addState(
            "// Step 3: Insert \"Cheri\"\n" +
            "fruits.asyncAdd([Fruit.id: 4, Fruit.name: \"Cheri\"])",
            {
                fruits.asyncAdd([Fruit.id: 4, Fruit.name: "Cheri"])
            }
        )

        addState(
            "// Step 4: Fix spelling of \"Cherry\" by updating the source relation\n" +
            "fruits.asyncUpdate(Fruit.id *== 4, newValues: [Fruit.name: \"Cherry\"])",
            {
                fruits.asyncUpdate(Fruit.id *== 4, newValues: [Fruit.name: "Cherry"])
            }
        )

        addState(
            "// Step 5: Mark \"Bandana\" as the selected fruit\n" +
            "selectedFruitIDs.asyncUpdate(true, newValues: [SelectedFruit.id: 3])",
            {
                selectedFruitIDs.asyncUpdate(true, newValues: [SelectedFruit.fruitID: 3])
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

        // Add observers that print out changes made to each relation
        func addLoggingObserver(to relation: Relation, name: String, orderedAttrs: [Attribute], changes: MutableValueProperty<String>) {
            let observer = LoggingObserver(relationName: name, orderedAttrs: orderedAttrs, changes: changes)
            let removal = relation.addAsyncObserver(observer)
            observerRemovals.append(removal)
        }
        addLoggingObserver(to: fruits, name: "fruits", orderedAttrs: [Fruit.id, Fruit.name], changes: fruitsChangesText)
        addLoggingObserver(to: selectedFruitIDs, name: "selectedFruitIDs", orderedAttrs: [SelectedFruit._id, SelectedFruit.fruitID], changes: selectedFruitIDsChangesText)
        addLoggingObserver(to: selectedFruits, name: "selectedFruits", orderedAttrs: [Fruit.id, Fruit.name], changes: selectedFruitsChangesText)
    }
    
    deinit {
        observerRemovals.forEach{ $0() }
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
    
    lazy var rawChangesText: ReadableProperty<String> = {
        let second: ReadableProperty<(String, String)> = zip(self.selectedFruitIDsChangesText, self.selectedFruitsChangesText)
        return zip(self.fruitsChangesText, second)
            .map{ (p0, p1) in
                var accum = ""

                func append(_ s: String) {
                    if !s.isEmpty {
                        accum.append(s + "\n")
                    }
                }

                append(p0)
                append(p1.0)
                append(p1.1)
                
                return accum
            }
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
            let state = self.states[currentStateIndex]
            self.lastPlayedIndex.change(currentStateIndex)
            self.performAnimations([
                self.animation(fast: false, snapshot: state.after)
            ])
            print("\n" + state.desc + "\n")
        } else {
            // Go forward to the next state
            let newStateIndex = currentStateIndex + 1
            if newStateIndex >= self.states.count { return }
            self.stateIndex.change(newStateIndex)
            self.clearChangesText()
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
    
    private func clearChangesText() {
        fruitsChangesText.change("")
        selectedFruitIDsChangesText.change("")
        selectedFruitsChangesText.change("")
    }
}

private class LoggingObserver: AsyncRelationChangeCoalescedObserver {
    
    private let relationName: String
    private let orderedAttrs: [Attribute]
    private let changes: MutableValueProperty<String>
    
    init(relationName: String, orderedAttrs: [Attribute], changes: MutableValueProperty<String>) {
        self.relationName = relationName
        self.orderedAttrs = orderedAttrs
        self.changes = changes
    }
    
    func relationWillChange(_ relation: Relation) {
    }
    
    func relationDidChange(_ relation: Relation, result: Result<RowChange, RelationError>) {
        let rowSet = result.ok!
        
        var string = ""
        func log(_ s: String) {
            print(s)
            string += s + "\n"
        }
        
        func strongSep() {
            log("============================")
        }

        func weakSep() {
            log("----------------------------")
        }

        func pretty(_ row: Row) -> String {
            let pairs: [String] = orderedAttrs.map{
                return "\($0): \(row[$0])"
            }
            return "[\(pairs.joined(separator: ", "))]"
        }
        
        func sortedDescriptions(for rows: Set<Row>) -> [String] {
            let orderAttr = orderedAttrs.first!
            return Array(rows)
                .sorted(by: { (r0, r1) in r0[orderAttr] < r1[orderAttr] })
                .map(pretty)
        }
        
        func logRows(_ rows: Set<Row>) {
            sortedDescriptions(for: rows).forEach(log)
        }

        if !rowSet.added.isEmpty || !rowSet.removed.isEmpty {
            strongSep()
            log(self.relationName)
            if !rowSet.added.isEmpty {
                weakSep()
                log("Added")
                logRows(rowSet.added)
            }
            if !rowSet.removed.isEmpty {
                weakSep()
                log("Removed")
                logRows(rowSet.removed)
            }
            strongSep()
            log("")
        }
        
        changes.change(string)
    }
}
