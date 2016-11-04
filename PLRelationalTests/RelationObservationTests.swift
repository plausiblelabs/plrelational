//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import PLRelational


class RelationObservationTests: DBTestCase {
    func testUniqueObservation() {
        let a = ChangeLoggingRelation(baseRelation:
            MakeRelation(
                ["id", "name", "type"]))
        
        let u = a.unique("type", matching: "animal")
        var lastChange: RelationChange?
        _ = u.addChangeObserver({ lastChange = $0 })
        
        lastChange = nil
        _ = a.add(["id": 1, "name": "cat", "type": "animal"])
        AssertEqual(lastChange?.added,
                    MakeRelation(
                        ["id", "name", "type"],
                        [1,    "cat",  "animal"]))
        AssertEqual(lastChange?.removed, nil)
        
        lastChange = nil
        _ = a.add(["id": 2, "name": "dog", "type": "animal"])
        AssertEqual(lastChange?.added,
                    MakeRelation(
                        ["id", "name", "type"],
                        [2,    "dog",  "animal"]))
        AssertEqual(lastChange?.removed, nil)
        
        lastChange = nil
        _ = a.add(["id": 3, "name": "corn", "type": "plant"])
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed,
                    MakeRelation(
                        ["id", "name", "type"],
                        [1,    "cat",  "animal"],
                        [2,    "dog",  "animal"]))
        
        lastChange = nil
        _ = a.delete(true)
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed, nil)
        
        lastChange = nil
        _ = a.add(["id": 1, "name": "cat", "type": "animal"])
        AssertEqual(lastChange?.added,
                    MakeRelation(
                        ["id", "name", "type"],
                        [1,    "cat",  "animal"]))
        AssertEqual(lastChange?.removed, nil)
        
        lastChange = nil
        _ = a.delete(true)
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed,
                    MakeRelation(
                        ["id", "name", "type"],
                        [1,    "cat",  "animal"]))
    }
    
    func thoroughObservationForOperator(_ opF: (Relation, Relation) -> Relation) -> RelationChange? {
        let sqliteDB = makeDB().db
        let initial = MakeRelation(
            ["n", "A", "B"],
            [ 1,   1,   0 ],
            [ 2,   1,   1 ],
            [ 3,   0,   0 ],
            [ 4,   0,   1 ],
            [ 5,   0,   1 ],
            [ 6,   0,   0 ],
            [ 7,   0,   0 ],
            [ 8,   0,   1 ],
            [ 9,   1,   1 ],
            [10,   1,   0 ],
            [11,   1,   0 ],
            [12,   1,   1 ]
        )
        
        let sqliteBase = sqliteDB.createRelation("base", scheme: initial.scheme).ok!
        for row in initial.rows() {
            let result = sqliteBase.add(row.ok!)
            XCTAssertNil(result.err)
        }
        
        let db = TransactionalDatabase(sqliteDB)
        let base = db["base"]
        
        let a = base.select(Attribute("A") *== 1).project(["n"])
        let b = base.select(Attribute("B") *== 1).project(["n"])
        let combined = opF(a, b)
        
        var lastChange: RelationChange?
        _ = combined.addChangeObserver({ lastChange = $0 })
        
        db.transaction({
            _ = base.update(Attribute("n") *==  1, newValues: ["A": 1, "B": 1])
            _ = base.update(Attribute("n") *==  2, newValues: ["A": 1, "B": 0])
            _ = base.update(Attribute("n") *==  3, newValues: ["A": 0, "B": 1])
            _ = base.update(Attribute("n") *==  4, newValues: ["A": 0, "B": 0])
            _ = base.update(Attribute("n") *==  5, newValues: ["A": 1, "B": 1])
            _ = base.update(Attribute("n") *==  6, newValues: ["A": 1, "B": 0])
            _ = base.update(Attribute("n") *==  7, newValues: ["A": 1, "B": 1])
            _ = base.update(Attribute("n") *==  8, newValues: ["A": 1, "B": 0])
            _ = base.update(Attribute("n") *==  9, newValues: ["A": 0, "B": 1])
            _ = base.update(Attribute("n") *== 10, newValues: ["A": 0, "B": 0])
            _ = base.update(Attribute("n") *== 11, newValues: ["A": 0, "B": 1])
            _ = base.update(Attribute("n") *== 12, newValues: ["A": 0, "B": 0])
        })
        
        return lastChange
    }
    
    func testUnionObservationThoroughly() {
        let change = thoroughObservationForOperator({ $0.union($1) })
        
        AssertEqual(change?.added,   MakeRelation(["n"], [ 3], [ 6], [ 7]))
        AssertEqual(change?.removed, MakeRelation(["n"], [ 4], [10], [12]))
    }
    
    func testIntersectionObservationThoroughly() {
        let change = thoroughObservationForOperator({ $0.intersection($1) })
        
        AssertEqual(change?.added,   MakeRelation(["n"], [ 1], [ 5], [ 7]))
        AssertEqual(change?.removed, MakeRelation(["n"], [ 2], [ 9], [12]))
    }
    
    func testDifferenceObservationThoroughly() {
        let change = thoroughObservationForOperator({ $0.difference($1) })
        
        AssertEqual(change?.added,   MakeRelation(["n"], [ 2], [ 6], [ 8]))
        AssertEqual(change?.removed, MakeRelation(["n"], [ 1], [10], [11]))
    }
    
    func testSelectExpressionMutation() {
        let concrete = MakeRelation(
            ["number", "word"],
            [1, "one"],
            [2, "two"],
            [3, "three"])
        
        let select = concrete.mutableSelect(Attribute("number") *== 1 *|| Attribute("word") *== "two")
        var lastChange: RelationChange?
        _ = select.addChangeObserver({ lastChange = $0 })
        
        let union = select.union(select)
        var lastChangeUnion: RelationChange?
        _ = union.addChangeObserver({ lastChangeUnion = $0 })
        
        AssertEqual(select, MakeRelation(
            ["number", "word"],
            [1, "one"],
            [2, "two"]))
        
        select.selectExpression = Attribute("number") *== 2 *|| Attribute("word") *== "three"
        AssertEqual(select, MakeRelation(
            ["number", "word"],
            [2, "two"],
            [3, "three"]))
        
        AssertEqual(lastChange?.added, MakeRelation(
            ["number", "word"],
            [3, "three"]))
        AssertEqual(lastChange?.removed, MakeRelation(
            ["number", "word"],
            [1, "one"]))
        
        AssertEqual(lastChangeUnion?.added, MakeRelation(
            ["number", "word"],
            [3, "three"]))
        AssertEqual(lastChangeUnion?.removed, MakeRelation(
            ["number", "word"],
            [1, "one"]))
        
        select.selectExpression = Attribute("number") *== 1 *|| Attribute("word") *== "two"
        AssertEqual(select, MakeRelation(
            ["number", "word"],
            [1, "one"],
            [2, "two"]))
        
        AssertEqual(lastChange?.added, MakeRelation(
            ["number", "word"],
            [1, "one"]))
        AssertEqual(lastChange?.removed, MakeRelation(
            ["number", "word"],
            [3, "three"]))
        
        AssertEqual(lastChangeUnion?.added, MakeRelation(
            ["number", "word"],
            [1, "one"]))
        AssertEqual(lastChangeUnion?.removed, MakeRelation(
            ["number", "word"],
            [3, "three"]))
    }
    
    func testObservationRemovalLeak() {
        let concrete = MakeRelation([])
        weak var shouldDeallocate: MutableSelectRelation?
        
        do {
            let select = concrete.mutableSelect(true)
            shouldDeallocate = select
            let removal = select.addChangeObserver({ _ in })
            removal()
        }
        XCTAssertNil(shouldDeallocate)
    }
    
    func testWeakObservationRemovalLeak() {
        let concrete = ConcreteRelation(scheme: [])
        weak var shouldDeallocate1: MutableSelectRelation?
        weak var shouldDeallocate2: MutableSelectRelation?
        
        do {
            let select1 = concrete.mutableSelect(true)
            shouldDeallocate1 = select1
            
            let select2 = select1.mutableSelect(true)
            shouldDeallocate2 = select2
            
            class Observer {
                func dummy(_: RelationChange) {}
            }
            let observer = Observer()
            select2.addWeakChangeObserver(observer, method: Observer.dummy)
        }
        XCTAssertNil(shouldDeallocate1)
        XCTAssertNil(shouldDeallocate2)
    }
    
    func testUnionObservation() {
        let a = ChangeLoggingRelation(baseRelation:
            MakeRelation(
                ["first", "last"],
                ["John", "Doe"]))
        let b = ChangeLoggingRelation(baseRelation:
            MakeRelation(
                ["first", "last"],
                ["Jane", "Doe"],
                ["Tim", "Smith"]))
        
        let u = a.union(b)
        var lastChange: RelationChange?
        _ = u.addChangeObserver({ lastChange = $0 })
        
        lastChange = nil
        _ = a.add(["first": "Sue", "last": "Johnson"])
        AssertEqual(lastChange?.added, ConcreteRelation(["first": "Sue", "last": "Johnson"]))
        AssertEqual(lastChange?.removed, nil)
        
        lastChange = nil
        _ = b.delete(Attribute("first") *== "Jane")
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed, ConcreteRelation(["first": "Jane", "last": "Doe"]))
        
        lastChange = nil
        _ = b.add(["first": "Sue", "last": "Johnson"])
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed, nil)
        
        lastChange = nil
        _ = a.delete(Attribute("first") *== "Sue")
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed, nil)
    }
    
    func testIntersectionObservation() {
        let a = ChangeLoggingRelation(baseRelation:
            MakeRelation(
                ["first", "last"],
                ["John", "Doe"]))
        let b = ChangeLoggingRelation(baseRelation:
            MakeRelation(
                ["first", "last"],
                ["Jane", "Doe"],
                ["Tim", "Smith"]))
        
        let i = a.intersection(b)
        var lastChange: RelationChange?
        _ = i.addChangeObserver({ lastChange = $0 })
        
        lastChange = nil
        _ = a.add(["first": "Sue", "last": "Johnson"])
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed, nil)
        
        lastChange = nil
        _ = b.delete(Attribute("first") *== "Jane")
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed, nil)
        
        lastChange = nil
        _ = b.add(["first": "Sue", "last": "Johnson"])
        AssertEqual(lastChange?.added, ConcreteRelation(["first": "Sue", "last": "Johnson"]))
        AssertEqual(lastChange?.removed, nil)
        
        lastChange = nil
        _ = a.delete(Attribute("first") *== "Sue")
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed, ConcreteRelation(["first": "Sue", "last": "Johnson"]))
    }
    
    func testDifferenceObservation() {
        let a = ChangeLoggingRelation(baseRelation:
            MakeRelation(
                ["first", "last"],
                ["John", "Doe"]))
        let b = ChangeLoggingRelation(baseRelation:
            MakeRelation(
                ["first", "last"],
                ["Jane", "Doe"],
                ["Tim", "Smith"]))
        
        let d = a.difference(b)
        var lastChange: RelationChange?
        _ = d.addChangeObserver({ lastChange = $0 })
        
        lastChange = nil
        _ = a.add(["first": "Sue", "last": "Johnson"])
        AssertEqual(lastChange?.added, ConcreteRelation(["first": "Sue", "last": "Johnson"]))
        AssertEqual(lastChange?.removed, nil)
        
        lastChange = nil
        _ = b.delete(Attribute("first") *== "Jane")
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed, nil)
        
        lastChange = nil
        _ = b.add(["first": "Sue", "last": "Johnson"])
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed, ConcreteRelation(["first": "Sue", "last": "Johnson"]))
        
        lastChange = nil
        _ = a.delete(Attribute("first") *== "Sue")
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed, nil)
    }
    
    func testProjectObservation() {
        let a = ChangeLoggingRelation(baseRelation:
            MakeRelation(
                ["first", "last"],
                ["John", "Doe"]))
        
        let p = a.project(["first"])
        var lastChange: RelationChange?
        _ = p.addChangeObserver({ lastChange = $0 })
        
        lastChange = nil
        _ = a.add(["first": "Sue", "last": "Johnson"])
        AssertEqual(lastChange?.added, ConcreteRelation(["first": "Sue"]))
        AssertEqual(lastChange?.removed, nil)
        
        lastChange = nil
        _ = a.update(Attribute("first") *== "Sue", newValues: ["last": "Jonsen"])
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed, nil)
        
        lastChange = nil
        _ = a.add(["first": "Sue", "last": "Thompson"])
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed, nil)
        
        lastChange = nil
        _ = a.delete(Attribute("last") *== "Jonsen")
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed, nil)
        
        lastChange = nil
        _ = a.delete(Attribute("last") *== "Thompson")
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed, ConcreteRelation(["first": "Sue"]))
    }
    
    func testSelectObservation() {
        let a = ChangeLoggingRelation(baseRelation:
            MakeRelation(
                ["first", "last"],
                ["John", "Doe"]))
        
        let s = a.select(Attribute("last") *== "Doe")
        var lastChange: RelationChange?
        _ = s.addChangeObserver({ lastChange = $0 })
        
        lastChange = nil
        _ = a.add(["first": "Sue", "last": "Doe"])
        AssertEqual(lastChange?.added, ConcreteRelation(["first": "Sue", "last": "Doe"]))
        AssertEqual(lastChange?.removed, nil)
        
        lastChange = nil
        _ = a.add(["first": "Sue", "last": "Thompson"])
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed, nil)
        
        lastChange = nil
        _ = a.delete(Attribute("first") *== "John")
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed, ConcreteRelation(["first": "John", "last": "Doe"]))
        
        lastChange = nil
        _ = a.delete(Attribute("last") *== "Thompson")
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed, nil)
    }
    
    func testJoinObservation() {
        let a = ChangeLoggingRelation(baseRelation:
            MakeRelation(
                ["first", "last"],
                ["John", "Doe"],
                ["Jane", "Doe"],
                ["Tom", "Smith"]))
        let b = ChangeLoggingRelation(baseRelation:
            MakeRelation(
                ["last", "remark"],
                ["Doe", "unknown"],
                ["Smith", "common"]))
        
        let j = a.join(b)
        var lastChange: RelationChange?
        _ = j.addChangeObserver({ lastChange = $0 })
        
        lastChange = nil
        _ = a.add(["first": "Sue", "last": "Doe"])
        AssertEqual(lastChange?.added, ConcreteRelation(["first": "Sue", "last": "Doe", "remark": "unknown"]))
        AssertEqual(lastChange?.removed, nil)
        
        lastChange = nil
        _ = a.delete(Attribute("first") *== "Sue")
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed, ConcreteRelation(["first": "Sue", "last": "Doe", "remark": "unknown"]))
        
        lastChange = nil
        _ = b.delete(Attribute("last") *== "Doe")
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed,
                    MakeRelation(
                        ["first", "last", "remark"],
                        ["John", "Doe", "unknown"],
                        ["Jane", "Doe", "unknown"]))
        
        lastChange = nil
        _ = b.add(["last": "Doe", "remark": "unknown"])
        AssertEqual(lastChange?.added,
                    MakeRelation(
                        ["first", "last", "remark"],
                        ["John", "Doe", "unknown"],
                        ["Jane", "Doe", "unknown"]))
        AssertEqual(lastChange?.removed, nil)
        
        lastChange = nil
        _ = b.add(["last": "DeLancey", "remark": "French"])
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed, nil)
    }
    
    func testRenameObservation() {
        let a = ChangeLoggingRelation(baseRelation:
            MakeRelation(
                ["first", "last"],
                ["John", "Doe"]))
        
        let r = a.renamePrime()
        var lastChange: RelationChange?
        _ = r.addChangeObserver({ lastChange = $0 })
        
        lastChange = nil
        _ = a.add(["first": "Sue", "last": "Doe"])
        AssertEqual(lastChange?.added, ConcreteRelation(["first'": "Sue", "last'": "Doe"]))
        AssertEqual(lastChange?.removed, nil)
        
        lastChange = nil
        _ = a.delete(Attribute("first") *== "John")
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed, ConcreteRelation(["first'": "John", "last'": "Doe"]))
    }
    
    func testUpdateObservation() {
        let a = ChangeLoggingRelation(baseRelation:
            MakeRelation(
                ["first", "last"],
                ["John", "Doe"]))
        
        let u = a.withUpdate(["last": "42"])
        var lastChange: RelationChange?
        _ = u.addChangeObserver({ lastChange = $0 })
        
        lastChange = nil
        _ = a.add(["first": "Sue", "last": "Smith"])
        AssertEqual(lastChange?.added, ConcreteRelation(["first": "Sue", "last": "42"]))
        AssertEqual(lastChange?.removed, nil)
        
        lastChange = nil
        _ = a.delete(Attribute("first") *== "John")
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed, ConcreteRelation(["first": "John", "last": "42"]))
    }
    
    func testMinObservation() {
        let a = ChangeLoggingRelation(baseRelation:
            MakeRelation(
                ["id", "name", "count"]))
        
        let m = a.min("count")
        var lastChange: RelationChange?
        _ = m.addChangeObserver({ lastChange = $0 })
        
        lastChange = nil
        _ = a.add(["id": 1, "name": "cat", "count": 2])
        AssertEqual(lastChange?.added, ConcreteRelation(["count": 2]))
        AssertEqual(lastChange?.removed, nil)
        
        lastChange = nil
        _ = a.add(["id": 2, "name": "dog", "count": 3])
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed, nil)
        
        lastChange = nil
        _ = a.update(Attribute("id") *== 2, newValues: ["count": 1])
        AssertEqual(lastChange?.added, ConcreteRelation(["count": 1]))
        AssertEqual(lastChange?.removed, ConcreteRelation(["count": 2]))
        
        lastChange = nil
        _ = a.delete(true)
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed, ConcreteRelation(["count": 1]))
    }
    
    func testMaxObservation() {
        let a = ChangeLoggingRelation(baseRelation:
            MakeRelation(
                ["id", "name", "count"]))
        
        let m = a.max("count")
        var lastChange: RelationChange?
        _ = m.addChangeObserver({ lastChange = $0 })
        
        lastChange = nil
        _ = a.add(["id": 1, "name": "cat", "count": 2])
        AssertEqual(lastChange?.added, ConcreteRelation(["count": 2]))
        AssertEqual(lastChange?.removed, nil)
        
        lastChange = nil
        _ = a.add(["id": 2, "name": "dog", "count": 1])
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed, nil)
        
        lastChange = nil
        _ = a.update(Attribute("id") *== 2, newValues: ["count": 4])
        AssertEqual(lastChange?.added, ConcreteRelation(["count": 4]))
        AssertEqual(lastChange?.removed, ConcreteRelation(["count": 2]))
        
        lastChange = nil
        _ = a.delete(true)
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed, ConcreteRelation(["count": 4]))
    }
    
    func testCountObservation() {
        let a = ChangeLoggingRelation(baseRelation:
            MakeRelation(
                ["id", "name"]))
        
        let c = a.count()
        var lastChange: RelationChange?
        _ = c.addChangeObserver({ lastChange = $0 })
        
        lastChange = nil
        _ = a.add(["id": 1, "name": "cat"])
        AssertEqual(lastChange?.added, ConcreteRelation(["count": 1]))
        AssertEqual(lastChange?.removed, ConcreteRelation(["count": 0]))
        
        lastChange = nil
        _ = a.add(["id": 2, "name": "dog"])
        AssertEqual(lastChange?.added, ConcreteRelation(["count": 2]))
        AssertEqual(lastChange?.removed, ConcreteRelation(["count": 1]))
        
        lastChange = nil
        _ = a.delete(true)
        AssertEqual(lastChange?.added, ConcreteRelation(["count": 0]))
        AssertEqual(lastChange?.removed, ConcreteRelation(["count": 2]))
    }
    
    func testOtherwiseObservation() {
        let a = ChangeLoggingRelation(baseRelation:
            MakeRelation(
                ["id", "name"]))
        let b = ChangeLoggingRelation(baseRelation:
            MakeRelation(
                ["id", "name"]))
        
        let o = a.otherwise(b)
        var lastChange: RelationChange?
        _ = o.addChangeObserver({ lastChange = $0 })
        
        lastChange = nil
        _ = b.add(["id": 1, "name": "cat"])
        AssertEqual(lastChange?.added,
                    MakeRelation(
                        ["id", "name"],
                        [1,    "cat"]))
        AssertEqual(lastChange?.removed, nil)
        
        lastChange = nil
        _ = a.add(["id": 2, "name": "dog"])
        AssertEqual(lastChange?.added,
                    MakeRelation(
                        ["id", "name"],
                        [2,    "dog"]))
        AssertEqual(lastChange?.removed,
                    MakeRelation(
                        ["id", "name"],
                        [1,    "cat"]))
        
        lastChange = nil
        _ = b.delete(true)
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed, nil)
        
        lastChange = nil
        _ = b.add(["id": 1, "name": "cat"])
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed, nil)
        
        lastChange = nil
        _ = a.delete(true)
        AssertEqual(lastChange?.added,
                    MakeRelation(
                        ["id", "name"],
                        [1,    "cat"]))
        AssertEqual(lastChange?.removed,
                    MakeRelation(
                        ["id", "name"],
                        [2,    "dog"]))
        
        lastChange = nil
        _ = b.delete(true)
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed,
                    MakeRelation(
                        ["id", "name"],
                        [1,    "cat"]))
    }
    
    func testComplexTransactionObservation() {
        let sqliteDB = makeDB().db
        let db = TransactionalDatabase(sqliteDB)
        func createRelation(_ name: String, _ scheme: Scheme) -> MutableRelation {
            let createResult = sqliteDB.createRelation(name, scheme: scheme)
            precondition(createResult.ok != nil)
            return db[name]
        }
        
        var collections = createRelation("collection", ["id", "type", "name", "parent", "order"])
        var objects = createRelation("object", ["id", "type", "name", "coll_id", "order"])
        var selectedCollectionID = createRelation("selected_collection", ["coll_id"])
        var selectedInspectorItemIDs = createRelation("selected_inspector_item", ["item_id"])
        
        let selectedCollection = selectedCollectionID
            .equijoin(collections, matching: ["coll_id": "id"])
            .project(["id", "type", "name"])
        
        let inspectorCollectionItems = selectedCollection
            .join(MakeRelation(["parent", "order"], [.null, 5.0]))
        let inspectorObjectItems = selectedCollectionID
            .join(objects)
            .renameAttributes(["coll_id": "parent"])
        let inspectorItems = inspectorCollectionItems
            .union(inspectorObjectItems)
        let selectedInspectorItems = selectedInspectorItemIDs
            .equijoin(inspectorItems, matching: ["item_id": "id"])
            .project(["id", "type", "name"])
        
        let selectedItems = selectedInspectorItems.otherwise(selectedCollection)
        let selectedItemTypes = selectedItems.project(["type"])
        
        var id: Int64 = 1
        var order: Double = 1.0
        
        func addCollection(_ name: String) {
            let row: Row = [
                "id": RelationValue(id),
                "type": "coll",
                "name": RelationValue(name),
                "parent": .null,
                "order": RelationValue(order)
            ]
            _ = collections.add(row)
            id += 1
            order += 1.0
        }
        
        func addObject(_ name: String) {
            let row: Row = [
                "id": RelationValue(id),
                "type": "obj",
                "name": RelationValue(name),
                "coll_id": 1,
                "order": RelationValue(order)
            ]
            _ = objects.add(row)
            id += 1
            order += 1.0
        }
        
        addCollection("Page1")
        addCollection("Page2")
        addObject("Obj1")
        addObject("Obj2")
        
        var lastChange: RelationChange?
        _ = selectedItemTypes.addChangeObserver({
            lastChange = $0
        })
        
        lastChange = nil
        _ = selectedCollectionID.add(["coll_id": 1])
        AssertEqual(lastChange?.added,
                    MakeRelation(
                        ["type"],
                        ["coll"]))
        AssertEqual(lastChange?.removed, nil)
        
        lastChange = nil
        _ = selectedInspectorItemIDs.add(["item_id": 3])
        AssertEqual(lastChange?.added,
                    MakeRelation(
                        ["type"],
                        ["obj"]))
        AssertEqual(lastChange?.removed,
                    MakeRelation(
                        ["type"],
                        ["coll"]))
        
        lastChange = nil
        _ = selectedInspectorItemIDs.delete(true)
        AssertEqual(lastChange?.added,
                    MakeRelation(
                        ["type"],
                        ["coll"]))
        AssertEqual(lastChange?.removed,
                    MakeRelation(
                        ["type"],
                        ["obj"]))
        
        lastChange = nil
        _ = selectedCollectionID.delete(true)
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed,
                    MakeRelation(
                        ["type"],
                        ["coll"]))
        
        lastChange = nil
        _ = selectedCollectionID.add(["coll_id": 1])
        AssertEqual(lastChange?.added,
                    MakeRelation(
                        ["type"],
                        ["coll"]))
        AssertEqual(lastChange?.removed, nil)
        
        lastChange = nil
        _ = selectedInspectorItemIDs.add(["item_id": 3])
        AssertEqual(lastChange?.added,
                    MakeRelation(
                        ["type"],
                        ["obj"]))
        AssertEqual(lastChange?.removed,
                    MakeRelation(
                        ["type"],
                        ["coll"]))
        
        lastChange = nil
        db.transaction{
            _ = selectedInspectorItemIDs.delete(true)
            _ = selectedCollectionID.delete(true)
            _ = selectedCollectionID.add(["coll_id": 2])
        }
        AssertEqual(lastChange?.added,
                    MakeRelation(
                        ["type"],
                        ["coll"]))
        AssertEqual(lastChange?.removed,
                    MakeRelation(
                        ["type"],
                        ["obj"]))
    }
    
    func testRedundantUnion() {
        let a = ChangeLoggingRelation(baseRelation:
            MakeRelation(
                ["id", "name", "type"]))
        let u = a.union(a)
        var lastChange: RelationChange?
        _ = u.addChangeObserver({ lastChange = $0 })
        
        lastChange = nil
        _ = a.add(["id": 1, "name": "cat", "type": "animal"])
        AssertEqual(lastChange?.added,
                    MakeRelation(
                        ["id", "name", "type"],
                        [1,    "cat",  "animal"]))
        AssertEqual(lastChange?.removed, nil)
        
        lastChange = nil
        _ = a.delete(true)
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed,
                    MakeRelation(
                        ["id", "name", "type"],
                        [1,    "cat",  "animal"]))
    }
    
    func testRedundantIntersection() {
        let a = ChangeLoggingRelation(baseRelation:
            MakeRelation(
                ["id", "name", "type"]))
        let i = a.intersection(a)
        var lastChange: RelationChange?
        _ = i.addChangeObserver({ lastChange = $0 })
        
        lastChange = nil
        _ = a.add(["id": 1, "name": "cat", "type": "animal"])
        AssertEqual(lastChange?.added,
                    MakeRelation(
                        ["id", "name", "type"],
                        [1,    "cat",  "animal"]))
        AssertEqual(lastChange?.removed, nil)
        
        lastChange = nil
        _ = a.delete(true)
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed,
                    MakeRelation(
                        ["id", "name", "type"],
                        [1,    "cat",  "animal"]))
    }
    
    func testRedundantDifference() {
        let a = ChangeLoggingRelation(baseRelation:
            MakeRelation(
                ["id", "name", "type"]))
        let i = a.difference(a)
        var lastChange: RelationChange?
        _ = i.addChangeObserver({ lastChange = $0 })
        
        lastChange = nil
        _ = a.add(["id": 1, "name": "cat", "type": "animal"])
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed, nil)
        
        lastChange = nil
        _ = a.delete(true)
        AssertEqual(lastChange?.added, nil)
        AssertEqual(lastChange?.removed, nil)
    }
    
}
