//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import PLRelational
import PLRelationalBinding
import PLBindableControls

class ViewModel {
    
    private let employees: Relation
    private let departments: Relation
    private let selectedEmployeeID: TransactionalRelation
    private let selectedEmployee: Relation
    
    private let undoableDB: UndoableDatabase
    
    init(undoManager: PLBindableControls.UndoManager) {
        
        func makeDB() -> (path: String, db: SQLiteDatabase) {
            let tmp = "/tmp" as NSString
            let dbname = "HelloWorldApp.db"
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
        employees = createRelation("employee", ["id", "first_name", "last_name", "dept_id"])
        departments = createRelation("department", ["dept_id", "title"])
        selectedEmployeeID = createRelation("selected_employee", ["id"])
        
        selectedEmployee = selectedEmployeeID
            .join(employees)
            .join(departments)
        
        undoableDB = UndoableDatabase(db: db, undoManager: undoManager)

        // Add some departments
        func addDepartment(_ id: Int64, _ title: String) {
            let row: Row = [
                "dept_id": RelationValue(id),
                "title": RelationValue(title)
            ]
            _ = sqliteDB["department"]!.add(row)
        }
        addDepartment(1, "Executive")
        addDepartment(2, "Safety")
        
        // Add some employees
        func addEmployee(_ id: Int64, _ first: String, _ last: String, _ deptID: Int64) {
            let row: Row = [
                "id": RelationValue(id),
                "first_name": RelationValue(first),
                "last_name": RelationValue(last),
                "dept_id": RelationValue(deptID)
            ]
            _ = sqliteDB["employee"]!.add(row)
        }
        addEmployee(1, "Montgomery", "Burns", 1)
        addEmployee(2, "Waylon", "Smithers", 1)
        addEmployee(3, "Homer", "Simpson", 2)
        addEmployee(4, "Lenny", "Leonard", 2)
        addEmployee(5, "Carl", "Carlson", 2)
    }

    lazy var employeesListModel: ListViewModel<RowArrayElement> = {
        return ListViewModel(
            data: self.employees.arrayProperty(idAttr: "id", orderAttr: "first_name"),
            contextMenu: nil,
            move: nil,
            cellIdentifier: { _ in "Cell" }
        )
    }()
    
    func employeeName(for rowID: Int64, initialValue: String?) -> AsyncReadWriteProperty<String> {
        let relation = self.employees
            .select(Attribute("id") *== RelationValue(rowID))
            .project(["first_name"])
        return self.undoableDB.bidiProperty(
            action: "Rename Employee",
            signal: relation.oneString(initialValue: initialValue),
            update: {
                relation.asyncUpdateString($0)
            }
        )
    }
    
    lazy var employeesListSelection: AsyncReadWriteProperty<Set<RelationValue>> = {
        return self.undoableDB.bidiProperty(
            action: "Change Selection",
            signal: self.selectedEmployeeID.allRelationValues(),
            update: { self.selectedEmployeeID.asyncReplaceValues(Array($0)) }
        )
    }()
    
    lazy var selectedEmployeeName: AsyncReadableProperty<String> = {
        return self.selectedEmployee
            .oneRow()
            .property()
            .map{ row in
                if let row = row {
                    let first: String = row["first_name"].get()!
                    let last: String = row["last_name"].get()!
                    return "\(last), \(first)"
                } else {
                    return "No selection"
                }
            }
    }()
    
    lazy var selectedEmployeeDepartment: AsyncReadableProperty<String> = {
        return self.selectedEmployee
            .project("title")
            .oneString()
            .property()
            .map{ $0.isEmpty ? "" : "Department: \($0)" }
    }()
}
