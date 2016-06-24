//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
@testable import Binding

class ValuePropertyTests: BindingTestCase {
    
    func testMutable() {
        let property = mutableValueProperty(false)
        
        var changeObserved = false
        _ = property.signal.observe({ _ in changeObserved = true })

        XCTAssertEqual(property.value, false)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false

        property.change(true, transient: false)
        XCTAssertEqual(property.value, true)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false

        property.change(true, transient: false)
        XCTAssertEqual(property.value, true)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
    }

    func testMap() {
        let property = mutableValueProperty(false)
        let mapped = property.map{ $0 ? 1 : 0 }
        var changeObserved = false
        _ = mapped.signal.observe({ _ in changeObserved = true })
        
        XCTAssertEqual(mapped.value, 0)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        property.change(true, transient: false)
        XCTAssertEqual(mapped.value, 1)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        property.change(true, transient: false)
        XCTAssertEqual(mapped.value, 1)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        property.change(false, transient: false)
        XCTAssertEqual(mapped.value, 0)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
    }
}
