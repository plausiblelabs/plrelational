//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import libRelational

class ModelDatabaseTests: DBTestCase {
    func testModels() {
        let db = makeDB().db
        
        let flights = [
            FLIGHT(owningDatabase: db, number: 42, departs: "Earth", arrives: "Space"),
            FLIGHT(owningDatabase: db, number: 99, departs: "JFK", arrives: "JFK"),
            FLIGHT(owningDatabase: db, number: 100, departs: "JFK", arrives: "SFO"),
            FLIGHT(owningDatabase: db, number: 123, departs: "Airport", arrives: "Another Airport"),
            FLIGHT(owningDatabase: db, number: 124, departs: "Q", arrives: "R"),
            ]
        
        for flight in flights {
            db.add(flight)
        }
        
        AssertEqual(db.fetchAll(FLIGHT.self), flights)
        AssertEqual(db.fetchAll(FLIGHT.self).select(FLIGHT.Attributes.departs *== "JFK"), flights.filter({ $0.departs == "JFK" }))
    }
    
    func testModelToMany() {
        let db = makeDB().db
        
        let store1 = Store(owningDatabase: db, name: "Joe's")
        XCTAssertNil(db.add(store1).err)
        
        let store2 = Store(owningDatabase: db, name: "CompuStern")
        XCTAssertNil(db.add(store2).err)
        
        let emp1 = Employee(owningDatabase: db, name: "Toddd")
        XCTAssertNil(store1.employees.ok!.add(emp1).err)
        
        let emp2 = Employee(owningDatabase: db, name: "Alex")
        XCTAssertNil(store1.employees.ok!.add(emp2).err)
        
        let emp3 = Employee(owningDatabase: db, name: "Ramius")
        XCTAssertNil(store1.employees.ok!.add(emp3).err)
        
        XCTAssertNil(emp1.directReports.ok!.add(emp2).err)
        XCTAssertNil(emp1.directReports.ok!.add(emp3).err)
        
        let emp4 = Employee(owningDatabase: db, name: "Phteven")
        XCTAssertNil(store2.employees.ok!.add(emp4).err)
        
        AssertEqual(store1.employees.ok!, [emp1, emp2, emp3])
        AssertEqual(store2.employees.ok!, [emp4])
        
        AssertEqual(emp1.directReports.ok!, [emp2, emp3])
        AssertEqual(emp2.directReports.ok!, [] as [Employee])
        
        XCTAssertEqual(emp2.parentOfType(Employee.self).ok??.toRow(), emp1.toRow())
        XCTAssertEqual(emp2.parentOfType(Store.self).ok??.toRow(), store1.toRow())
        
        let emp4Supervisor = emp4.parentOfType(Employee.self)
        XCTAssertNil(emp4Supervisor.err)
        emp4Supervisor.map({ XCTAssertNil($0) })
    }
    
    func testModelMutation() {
        let (path, db) = makeDB()
        
        let store = Store(owningDatabase: db, name: "Joe's")
        XCTAssertNil(db.add(store).err)
        
        let fetched = mapOk(db.fetchAll(Store.self), { $0 })
        XCTAssertNil(fetched.err)
        let fetchedStore = fetched.ok?.first
        XCTAssertTrue(store === fetchedStore)
        
        store.name = "Bob's"
        fetchedStore?.name = "Tom's"
        XCTAssertEqual(store.name, fetchedStore?.name)
        
        var changed = false
        store.changeObservers.add({ _ in changed = true })
        fetchedStore?.name = "Kate's"
        XCTAssertTrue(changed)
        
        let sqlite2 = try! SQLiteDatabase(path)
        let db2 = ModelDatabase(sqlite2)
        AssertEqual(db2.fetchAll(Store.self), fetched.ok ?? [])
    }
}
