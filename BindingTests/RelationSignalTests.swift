//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import libRelational
@testable import Binding

class RelationSignalTests: BindingTestCase {
    
    func testSignal() {
        let db = makeDB().db
        let sqlr = db.createRelation("animal", scheme: ["id", "name"]).ok!
        let r = ChangeLoggingRelation(baseRelation: sqlr)

        var willChangeCount = 0
        var didChangeCount = 0
        var changes: [String] = []
        
        let runloop = CFRunLoopGetCurrent()
        let group = dispatch_group_create()
        
        let signal = r.select(Attribute("id") *== 1).project(["name"]).signal{ $0.oneString($1) }
        _ = signal.observe(SignalObserver(
            valueWillChange: {
                willChangeCount += 1
            },
            valueChanging: { newValue, _ in changes.append(newValue) },
            valueDidChange: {
                didChangeCount += 1
                dispatch_group_leave(group)
                CFRunLoopStop(runloop)
            }
        ))
        
        // Verify that signal doesn't deliver changes until we actually start the signal
        XCTAssertEqual(changes, [])
        XCTAssertEqual(willChangeCount, 0)
        XCTAssertEqual(didChangeCount, 0)

        // Start the signal to trigger the async query and wait for it to complete
        dispatch_group_enter(group)
        signal.start()
        CFRunLoopRun()
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER)
        
        // Verify that a single value was delivered
        XCTAssertEqual(changes, [""])
        XCTAssertEqual(willChangeCount, 1)
        XCTAssertEqual(didChangeCount, 1)

        // TODO: Currently this is synchronous; need to change this test so that it verifies
        // behavior in an asynchronous environment
        r.add(["id": 1, "name": "cat"])
        XCTAssertEqual(changes, ["", "cat"])
        
        r.add(["id": 2, "name": "dog"])
        XCTAssertEqual(changes, ["", "cat"])
        
        r.delete(true)
        XCTAssertEqual(changes, ["", "cat", ""])
    }
}
