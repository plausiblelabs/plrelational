//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import PLRelational
import Binding
import BindableControls

class ViewModel {

    private var persons: MutableRelation
    private var selectedPersonID: MutableRelation
    private var personResults: MutableSelectRelation
    
    private let undoableDB: UndoableDatabase

    private var removals: [ObserverRemoval] = []
    
    init(undoManager: UndoManager) {
        
        func makeDB() -> (path: String, db: SQLiteDatabase) {
            let tmp = "/tmp" as NSString
            let dbname = "SearchApp.db"
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
        personResults = persons.mutableSelect(false)
        
        undoableDB = UndoableDatabase(db: db, undoManager: undoManager)

        _ = personResults.addChangeObserver({ _ in
            Swift.print("RESULTS: \(self.personResults)")
        })
        
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
    }
    
    deinit {
        removals.forEach{ $0() }
    }
    
    private lazy var queueScheduler: Scheduler = QueueScheduler()
    
    // ASYNC: Reads string changes on MAIN thread, writes to selectExpression on BG thread,
    lazy var queryString: ReadWriteProperty<String> = mutableValueProperty("", { [weak self] query, _ in
        self?.queueScheduler.schedule{ [weak self] in
            if query.isEmpty {
                self?.personResults.selectExpression = false
            } else {
                self?.personResults.selectExpression = SelectExpressionBinaryOperator(lhs: Attribute("name"), op: GlobComparator(), rhs: "\(query)*")
            }
        }
    })
    
    lazy var personResultsArray: ArrayProperty<RowArrayElement> = { [unowned self] in
        return self.personResults.arrayProperty()
    }()
    
    lazy var listViewModel: ListViewModel<RowArrayElement> = { [unowned self] in
        
        // ASYNC: Reads values on MAIN thread, writes to relation on MAIN thread
        func selectionProperty(relation: MutableRelation) -> ReadWriteProperty<Set<RelationValue>> {
            return self.undoableDB.bidiProperty(
                relation,
                action: "Change Selection",
                get: { $0.allValues },
                set: { relation.replaceValues(Array($0)) }
            )
        }

        // ASYNC: Reads value on MAIN thread
        func cellString(row: Row) -> String {
            return "\(row["name"]) (\(row["sales"]))"
        }
        
        return ListViewModel(
            // ASYNC: Changes from relation calculated on BG thread, reported on MAIN thread
            data: self.personResultsArray,
            contextMenu: nil,
            move: nil,
            selection: selectionProperty(self.selectedPersonID),
            cellIdentifier: { _ in "Cell" },
            cellText: { row in
                let rowID = row["id"]
                let cellText = self.persons
                    .select(Attribute("id") *== rowID)
                    .property{ $0.oneValue(cellString, orDefault: "") }
                return .ReadOnly(cellText)
            },
            cellImage: nil
        )
    }()
    
    // ASYNC: Should resolve to `true` when `personResultsArray` is in `Computing` state
    // TODO: Hmm, background work actually begins when `queryString` updates the select expression,
    // but here we only show progress indicator once the changes make their way to `personResultsArray`
    lazy var progressVisible: ReadableProperty<Bool> = { [unowned self] in
        // TODO
        //return self.personResultsArray.map{ $0.isComputing }
        return constantValueProperty(false)
    }()
    
    // ASYNC: Reads value on MAIN thread (since `selectedPersonID` relation is in-memory only)
    lazy var recordDisabled: ReadableProperty<Bool> = { [unowned self] in
        return self.selectedPersonID.empty
    }()

    // ASYNC: Reads clicks on MAIN thread, writes to relation on MAIN thread (assuming in-memory relation)
    lazy var recordClicked: ActionProperty = ActionProperty {
        Swift.print("TODO: INCREMENT SALES")
    }

    // ASYNC: Reads value on MAIN thread (assuming changes are stored in-memory only)
    lazy var saveDisabled: ReadableProperty<Bool> = { [unowned self] in
        // TODO: Return true only when there are no changes
        return constantValueProperty(true)
    }()

    // ASYNC: Reads clicks on MAIN thread, writes to SQLite relation on BG thread
    lazy var saveClicked: ActionProperty = ActionProperty {
        Swift.print("TODO: SAVE CHANGES")
    }
}
