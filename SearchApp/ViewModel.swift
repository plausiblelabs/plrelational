//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import libRelational
import Binding
import BindableControls

class ViewModel {

    private var persons: MutableRelation
    private var selectedPersonID: MutableRelation
    private var personResults: MutableSelectIntermediateRelation
    
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
    
    lazy var queryString: MutableObservableValue<String> = { [unowned self] in
        let query = mutableObservableValue("")
        let removal = query.addChangeObserver({ _ in
            if query.value.isEmpty {
                self.personResults.selectExpression = false
            } else {
                self.personResults.selectExpression = SelectExpressionBinaryOperator(lhs: Attribute("name"), op: GlobComparator(), rhs: "\(query.value)*")
            }
        })
        self.removals.append(removal)
        return query
    }()
    
    lazy var listViewModel: ListViewModel<RowArrayElement> = { [unowned self] in
        
        func selectionBinding(relation: MutableRelation) -> MutableObservableValue<Set<RelationValue>> {
            return self.undoableDB.observe(
                relation,
                action: "Change Selection",
                get: { $0.allValues },
                set: { relation.replaceValues(Array($0)) }
            )
        }
        
        func cellString(row: Row) -> String {
            return "\(row["name"]) (\(row["sales"]))"
        }
        
        return ListViewModel(
            data: self.personResults.observableArray(),
            contextMenu: nil,
            move: nil,
            selection: selectionBinding(self.selectedPersonID),
            cellIdentifier: { _ in "Cell" },
            cellText: { row in
                let rowID = row["id"]
                return self.persons
                    .select(Attribute("id") *== rowID)
                    .observable{ $0.oneValue(cellString, orDefault: "") }
            },
            cellImage: nil
        )
    }()
    
    let progressVisible: ObservableValue<Bool> = ObservableValue.constant(false)
    
    lazy var recordDisabled: ObservableValue<Bool> = { [unowned self] in
        return self.selectedPersonID.empty
    }()

    lazy var recordClicked: MutableObservableValue<Bool> = { [unowned self] in
        let clicked = mutableObservableValue(false)
        let removal = clicked.addChangeObserver({ _ in
            if clicked.value {
                Swift.print("TODO: INCREMENT SALES")
            }
        })
        self.removals.append(removal)
        return clicked
    }()

    lazy var saveDisabled: ObservableValue<Bool> = { [unowned self] in
        // TODO: Return true only when there are no changes
        return ObservableValue.constant(true)
    }()
    
    lazy var saveClicked: MutableObservableValue<Bool> = { [unowned self] in
        let clicked = mutableObservableValue(false)
        let removal = clicked.addChangeObserver({ _ in
            if clicked.value {
                Swift.print("TODO: SAVE CHANGES")
            }
        })
        self.removals.append(removal)
        return clicked
    }()
}