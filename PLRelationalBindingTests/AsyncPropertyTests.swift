//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
@testable import PLRelationalBinding

class AsyncPropertyTests: BindingTestCase {
    
    func verify<P: AsyncReadablePropertyType, T: Equatable>(_ property: P, _ observer: TestObserver<T>,
                value: T?, changes: [T], willChangeCount: Int, didChangeCount: Int,
                file: StaticString = #file, line: UInt = #line) where P.Value == T
    {
        XCTAssertEqual(property.value, value, file: file, line: line)
        XCTAssertEqual(observer.changes, changes, file: file, line: line)
        XCTAssertEqual(observer.willChangeCount, willChangeCount, file: file, line: line)
        XCTAssertEqual(observer.didChangeCount, didChangeCount, file: file, line: line)
    }

    func testConstantValueAsyncProperty() {
        let property = constantValueAsyncProperty(false)
        let observer1 = BoolObserver()
        let observer2 = BoolObserver()
        
        // Verify initial property value
        verify(property, observer1, value: nil, changes: [], willChangeCount: 0, didChangeCount: 0)
        verify(property, observer2, value: nil, changes: [], willChangeCount: 0, didChangeCount: 0)
        
        // Verify that the current property value is delivered when observer is attached
        let removal1 = observer1.observe(property.signal)
        verify(property, observer1, value: false, changes: [false], willChangeCount: 0, didChangeCount: 0)
        verify(property, observer2, value: false, changes: [], willChangeCount: 0, didChangeCount: 0)
        
        let removal2 = observer2.observe(property.signal)
        verify(property, observer1, value: false, changes: [false], willChangeCount: 0, didChangeCount: 0)
        verify(property, observer2, value: false, changes: [false], willChangeCount: 0, didChangeCount: 0)
        
        removal1()
        removal2()
    }

    func testLiftSynchronousPropertyToAsync() {
        let syncProperty = mutableValueProperty("1")
        let asyncProperty = syncProperty.async()

        let observer = StringObserver()
        verify(asyncProperty, observer, value: nil, changes: [], willChangeCount: 0, didChangeCount: 0)

        let removal = observer.observe(asyncProperty.signal)
        XCTAssertEqual(syncProperty.value, "1")
        verify(asyncProperty, observer, value: "1", changes: ["1"], willChangeCount: 0, didChangeCount: 0)

        syncProperty.change("2", transient: false)
        XCTAssertEqual(syncProperty.value, "2")
        verify(asyncProperty, observer, value: "2", changes: ["1", "2"], willChangeCount: 0, didChangeCount: 0)
        
        removal()
    }
}
