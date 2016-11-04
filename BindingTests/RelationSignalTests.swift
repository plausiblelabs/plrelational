//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import PLRelational
@testable import Binding

class RelationSignalTests: BindingTestCase {
    
    func testSignal() {
        let sqliteDB = makeDB().db
        _ = sqliteDB.createRelation("animal", scheme: ["id", "name"]).ok!
        let db = TransactionalDatabase(sqliteDB)
        let r = db["animal"]

        var willChangeCount = 0
        var didChangeCount = 0
        var changes: [String] = []
        
        let runloop = CFRunLoopGetCurrent()

        func awaitCompletion(_ f: () -> Void) {
            f()
            CFRunLoopRun()
        }
        
        let signal = r.select(Attribute("id") *== 1).project(["name"]).signal{ $0.oneString($1) }
        _ = signal.observe(SignalObserver(
            valueWillChange: {
                willChangeCount += 1
            },
            valueChanging: { newValue, _ in changes.append(newValue) },
            valueDidChange: {
                didChangeCount += 1
                CFRunLoopStop(runloop)
            }
        ))
        
        // Verify that signal doesn't deliver changes until we actually start the signal
        XCTAssertEqual(changes, [])
        XCTAssertEqual(willChangeCount, 0)
        XCTAssertEqual(didChangeCount, 0)

        // Start the signal to trigger the async query and wait for it to complete
        awaitCompletion{ signal.start(deliverInitial: true) }
        XCTAssertEqual(changes, [""])
        XCTAssertEqual(willChangeCount, 1)
        XCTAssertEqual(didChangeCount, 1)

        // Perform an async update to the underlying relation
        awaitCompletion{ r.asyncAdd(["id": 1, "name": "cat"]) }
        XCTAssertEqual(changes, ["", "cat"])
        XCTAssertEqual(willChangeCount, 2)
        XCTAssertEqual(didChangeCount, 2)

        // Perform another async update to the underlying relation (except this one isn't relevant to the
        // `select` that our signal is built on, so the signal shouldn't deliver a change)
        awaitCompletion{ r.asyncAdd(["id": 2, "name": "dog"]) }
        XCTAssertEqual(changes, ["", "cat"])
        XCTAssertEqual(willChangeCount, 3)
        XCTAssertEqual(didChangeCount, 3)

        // Perform an async delete-all-rows on the underlying relation
        awaitCompletion{ r.asyncDelete(true) }
        XCTAssertEqual(changes, ["", "cat", ""])
        XCTAssertEqual(willChangeCount, 4)
        XCTAssertEqual(didChangeCount, 4)
    }
}
