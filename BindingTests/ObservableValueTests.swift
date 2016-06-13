//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
@testable import Binding

class ObservableValueTests: BindingTestCase {
    
    func testMap() {
        let observable = mutableObservableValue(false)
        let mapped = observable.map{ $0 ? 1 : 0 }
        var changed = false
        _ = mapped.addChangeObserver({ _ in changed = true })
        let metadata = ChangeMetadata(transient: false)
        
        XCTAssertEqual(mapped.value, 0)
        XCTAssertEqual(changed, false)
        changed = false

        observable.update(true, metadata)
        XCTAssertEqual(mapped.value, 1)
        XCTAssertEqual(changed, true)
        changed = false
        
        observable.update(true, metadata)
        XCTAssertEqual(mapped.value, 1)
        XCTAssertEqual(changed, false)
        changed = false
        
        observable.update(false, metadata)
        XCTAssertEqual(mapped.value, 0)
        XCTAssertEqual(changed, true)
        changed = false
    }
    
    func testZip() {
        let observable1 = mutableObservableValue(false)
        let observable2 = mutableObservableValue(false)
        let zipped = observable1.zip(observable2)
        var changed = false
        _ = zipped.addChangeObserver({ _ in changed = true })
        let metadata = ChangeMetadata(transient: false)

        XCTAssertEqual(zipped.value.0, false)
        XCTAssertEqual(zipped.value.1, false)
        XCTAssertEqual(changed, false)
        changed = false
        
        observable1.update(true, metadata)
        XCTAssertEqual(zipped.value.0, true)
        XCTAssertEqual(zipped.value.1, false)
        XCTAssertEqual(changed, true)
        changed = false
        
        observable2.update(true, metadata)
        XCTAssertEqual(zipped.value.0, true)
        XCTAssertEqual(zipped.value.1, true)
        XCTAssertEqual(changed, true)
        changed = false
        
        observable2.update(true, metadata)
        XCTAssertEqual(zipped.value.0, true)
        XCTAssertEqual(zipped.value.1, true)
        XCTAssertEqual(changed, false)
        changed = false
    }
    
    func testMutableObservableBool() {
        let observable = mutableObservableValue(false)
        var changed = false
        _ = observable.addChangeObserver({ _ in changed = true })
        let metadata = ChangeMetadata(transient: false)

        XCTAssertEqual(observable.value, false)
        XCTAssertEqual(changed, false)
        changed = false

        observable.toggle(metadata)
        XCTAssertEqual(observable.value, true)
        XCTAssertEqual(changed, true)
        changed = false

        observable.toggle(metadata)
        XCTAssertEqual(observable.value, false)
        XCTAssertEqual(changed, true)
        changed = false

        observable.update(true, metadata)
        XCTAssertEqual(observable.value, true)
        XCTAssertEqual(changed, true)
        changed = false

        observable.update(true, metadata)
        XCTAssertEqual(observable.value, true)
        XCTAssertEqual(changed, false)
        changed = false
    }
}
