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
    
    func testZip() {
        let property1 = mutableValueProperty(false)
        let property2 = mutableValueProperty(false)
        let zipped = zip(property1, property2)
        var changeObserved = false
        _ = zipped.signal.observe({ _ in changeObserved = true })
        
        XCTAssertEqual(zipped.value.0, false)
        XCTAssertEqual(zipped.value.1, false)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        property1.change(true, transient: false)
        XCTAssertEqual(zipped.value.0, true)
        XCTAssertEqual(zipped.value.1, false)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        property2.change(true, transient: false)
        XCTAssertEqual(zipped.value.0, true)
        XCTAssertEqual(zipped.value.1, true)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        property2.change(true, transient: false)
        XCTAssertEqual(zipped.value.0, true)
        XCTAssertEqual(zipped.value.1, true)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
    }
    
    func testNot() {
        let property = mutableValueProperty(false)
        let mapped = not(property)
        var changeObserved = false
        _ = mapped.signal.observe({ _ in changeObserved = true })
        
        XCTAssertEqual(mapped.value, true)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        property.change(true, transient: false)
        XCTAssertEqual(mapped.value, false)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        property.change(true, transient: false)
        XCTAssertEqual(mapped.value, false)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        property.change(false, transient: false)
        XCTAssertEqual(mapped.value, true)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
    }
    
    func testOr() {
        let property1 = mutableValueProperty(false)
        let property2 = mutableValueProperty(false)
        let mapped = property1 *|| property2
        var changeObserved = false
        _ = mapped.signal.observe({ _ in changeObserved = true })
        
        XCTAssertEqual(mapped.value, false)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        property1.change(true, transient: false)
        XCTAssertEqual(mapped.value, true)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        property2.change(true, transient: false)
        XCTAssertEqual(mapped.value, true)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        property2.change(false, transient: false)
        XCTAssertEqual(mapped.value, true)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        property1.change(false, transient: false)
        XCTAssertEqual(mapped.value, false)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
    }
    
    func testAnd() {
        let property1 = mutableValueProperty(false)
        let property2 = mutableValueProperty(false)
        let mapped = property1 *&& property2
        var changeObserved = false
        _ = mapped.signal.observe({ _ in changeObserved = true })
        
        XCTAssertEqual(mapped.value, false)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        property1.change(true, transient: false)
        XCTAssertEqual(mapped.value, false)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        property2.change(true, transient: false)
        XCTAssertEqual(mapped.value, true)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        property2.change(false, transient: false)
        XCTAssertEqual(mapped.value, false)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        property1.change(false, transient: false)
        XCTAssertEqual(mapped.value, false)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
    }
    
    func testEq() {
        let property1 = mutableValueProperty(0)
        let property2 = mutableValueProperty(1)
        let mapped = property1 *== property2
        var changeObserved = false
        _ = mapped.signal.observe({ _ in changeObserved = true })
        
        XCTAssertEqual(mapped.value, false)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        property1.change(2, transient: false)
        XCTAssertEqual(mapped.value, false)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        property2.change(2, transient: false)
        XCTAssertEqual(mapped.value, true)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        property2.change(3, transient: false)
        XCTAssertEqual(mapped.value, false)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        property1.change(4, transient: false)
        XCTAssertEqual(mapped.value, false)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
    }
    
    func testThen() {
        var count = 0
        let property = mutableValueProperty(false)
        let then = property.then{ count += 1 }
        var changeObserved = false
        _ = then.signal.observe({ _ in changeObserved = true })
        
        XCTAssertEqual(count, 0)
        XCTAssertEqual(changeObserved, false)
        
        property.change(false, transient: false)
        XCTAssertEqual(count, 0)
        XCTAssertEqual(changeObserved, false)
        
        property.change(true, transient: false)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(changeObserved, false)
        
        property.change(true, transient: false)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(changeObserved, false)
        
        property.change(false, transient: false)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(changeObserved, false)
        
        property.change(true, transient: false)
        XCTAssertEqual(count, 2)
        XCTAssertEqual(changeObserved, false)
    }
    
    func testAnyTrue() {
        let property1 = mutableValueProperty(false)
        let property2 = mutableValueProperty(false)
        let properties: [MutableValueProperty<Bool>] = [property1, property2]
        let mapped = properties.anyTrue()
        var changeObserved = false
        _ = mapped.signal.observe({ _ in changeObserved = true })
        
        XCTAssertEqual(mapped.value, false)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        property1.change(true, transient: false)
        XCTAssertEqual(mapped.value, true)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        property2.change(true, transient: false)
        XCTAssertEqual(mapped.value, true)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        property2.change(false, transient: false)
        XCTAssertEqual(mapped.value, true)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        property1.change(false, transient: false)
        XCTAssertEqual(mapped.value, false)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
    }
    
    func testAllTrue() {
        let property1 = mutableValueProperty(false)
        let property2 = mutableValueProperty(false)
        let properties: [MutableValueProperty<Bool>] = [property1, property2]
        let mapped = properties.allTrue()
        var changeObserved = false
        _ = mapped.signal.observe({ _ in changeObserved = true })
        
        XCTAssertEqual(mapped.value, false)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        property1.change(true, transient: false)
        XCTAssertEqual(mapped.value, false)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        property2.change(true, transient: false)
        XCTAssertEqual(mapped.value, true)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        property2.change(false, transient: false)
        XCTAssertEqual(mapped.value, false)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        property1.change(false, transient: false)
        XCTAssertEqual(mapped.value, false)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
    }
    
    func testNoneTrue() {
        let property1 = mutableValueProperty(false)
        let property2 = mutableValueProperty(false)
        let properties: [MutableValueProperty<Bool>] = [property1, property2]
        let mapped = properties.noneTrue()
        var changeObserved = false
        _ = mapped.signal.observe({ _ in changeObserved = true })
        
        XCTAssertEqual(mapped.value, true)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        property1.change(true, transient: false)
        XCTAssertEqual(mapped.value, false)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        property2.change(true, transient: false)
        XCTAssertEqual(mapped.value, false)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        property2.change(false, transient: false)
        XCTAssertEqual(mapped.value, false)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        property1.change(false, transient: false)
        XCTAssertEqual(mapped.value, true)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
    }
    
    func testCommon() {
        // TODO
    }
}
