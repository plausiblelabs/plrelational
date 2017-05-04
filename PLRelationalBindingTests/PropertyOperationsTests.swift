//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
@testable import PLRelationalBinding

class PropertyOperationsTests: BindingTestCase {
    
    func testMap() {
        let property = mutableValueProperty(false)
        let mapped = property.map{ $0 ? 1 : 0 }
        let observer = IntObserver()

        func verify(value: Int, changes: [Int], willChangeCount: Int, didChangeCount: Int, file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(mapped.value, value, file: file, line: line)
            XCTAssertEqual(observer.changes, changes, file: file, line: line)
            XCTAssertEqual(observer.willChangeCount, willChangeCount, file: file, line: line)
            XCTAssertEqual(observer.didChangeCount, didChangeCount, file: file, line: line)
        }

        verify(value: 0, changes: [], willChangeCount: 0, didChangeCount: 0)

        let removal = observer.observe(mapped.signal)
        verify(value: 0, changes: [0], willChangeCount: 1, didChangeCount: 1)

        property.change(true, transient: false)
        verify(value: 1, changes: [0, 1], willChangeCount: 2, didChangeCount: 2)

        property.change(true, transient: false)
        verify(value: 1, changes: [0, 1], willChangeCount: 2, didChangeCount: 2)

        property.change(false, transient: false)
        verify(value: 0, changes: [0, 1, 0], willChangeCount: 3, didChangeCount: 3)
        
        removal()
    }

    func testZip() {
        let property1 = mutableValueProperty(false)
        let property2 = mutableValueProperty(false)
        let zipped = zip(property1, property2)
        let observer = TestObserver<(Bool, Bool)>()
        
        func verify(value: (Bool, Bool), changes: [(Bool, Bool)], willChangeCount: Int, didChangeCount: Int, file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(zipped.value.0, value.0, file: file, line: line)
            XCTAssertEqual(zipped.value.1, value.1, file: file, line: line)
            XCTAssertEqual(observer.changes.map{ $0.0 }, changes.map{ $0.0 }, file: file, line: line)
            XCTAssertEqual(observer.changes.map{ $0.1 }, changes.map{ $0.1 }, file: file, line: line)
            XCTAssertEqual(observer.willChangeCount, willChangeCount, file: file, line: line)
            XCTAssertEqual(observer.didChangeCount, didChangeCount, file: file, line: line)
        }
        
        verify(value: (false, false), changes: [], willChangeCount: 0, didChangeCount: 0)
        
        let removal = observer.observe(zipped.signal)
        verify(value: (false, false), changes: [(false, false)], willChangeCount: 2, didChangeCount: 2)

        property1.change(true, transient: false)
        verify(value: (true, false), changes: [(false, false), (true, false)], willChangeCount: 3, didChangeCount: 3)

        property2.change(true, transient: false)
        verify(value: (true, true), changes: [(false, false), (true, false), (true, true)], willChangeCount: 4, didChangeCount: 4)

        property2.change(true, transient: false)
        verify(value: (true, true), changes: [(false, false), (true, false), (true, true)], willChangeCount: 4, didChangeCount: 4)
        
        removal()
    }
    
    func testNot() {
        let property = mutableValueProperty(false)
        let mapped = not(property)
        let observer = BoolObserver()
        
        func verify(value: Bool, changes: [Bool], willChangeCount: Int, didChangeCount: Int, file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(mapped.value, value, file: file, line: line)
            XCTAssertEqual(observer.changes, changes, file: file, line: line)
            XCTAssertEqual(observer.willChangeCount, willChangeCount, file: file, line: line)
            XCTAssertEqual(observer.didChangeCount, didChangeCount, file: file, line: line)
        }
        
        verify(value: true, changes: [], willChangeCount: 0, didChangeCount: 0)
        
        let removal = observer.observe(mapped.signal)
        verify(value: true, changes: [true], willChangeCount: 1, didChangeCount: 1)
        
        property.change(true, transient: false)
        verify(value: false, changes: [true, false], willChangeCount: 2, didChangeCount: 2)
        
        property.change(true, transient: false)
        verify(value: false, changes: [true, false], willChangeCount: 2, didChangeCount: 2)
        
        property.change(false, transient: false)
        verify(value: true, changes: [true, false, true], willChangeCount: 3, didChangeCount: 3)
        
        removal()
    }

    func testOr() {
        let property1 = mutableValueProperty(false)
        let property2 = mutableValueProperty(false)
        let mapped = property1 *|| property2
        let observer = BoolObserver()
        
        func verify(value: Bool, changes: [Bool], willChangeCount: Int, didChangeCount: Int, file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(mapped.value, value, file: file, line: line)
            XCTAssertEqual(observer.changes, changes, file: file, line: line)
            XCTAssertEqual(observer.willChangeCount, willChangeCount, file: file, line: line)
            XCTAssertEqual(observer.didChangeCount, didChangeCount, file: file, line: line)
        }
        
        verify(value: false, changes: [], willChangeCount: 0, didChangeCount: 0)
        
        let removal = observer.observe(mapped.signal)
        verify(value: false, changes: [false], willChangeCount: 2, didChangeCount: 2)
        
        property1.change(true, transient: false)
        verify(value: true, changes: [false, true], willChangeCount: 3, didChangeCount: 3)

        property2.change(true, transient: false)
        verify(value: true, changes: [false, true], willChangeCount: 4, didChangeCount: 4)

        property2.change(false, transient: false)
        verify(value: true, changes: [false, true], willChangeCount: 5, didChangeCount: 5)

        property1.change(false, transient: false)
        verify(value: false, changes: [false, true, false], willChangeCount: 6, didChangeCount: 6)
        
        removal()
    }

    func testAnd() {
        let property1 = mutableValueProperty(false)
        let property2 = mutableValueProperty(false)
        let mapped = property1 *&& property2
        let observer = BoolObserver()
        
        func verify(value: Bool, changes: [Bool], willChangeCount: Int, didChangeCount: Int, file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(mapped.value, value, file: file, line: line)
            XCTAssertEqual(observer.changes, changes, file: file, line: line)
            XCTAssertEqual(observer.willChangeCount, willChangeCount, file: file, line: line)
            XCTAssertEqual(observer.didChangeCount, didChangeCount, file: file, line: line)
        }
        
        verify(value: false, changes: [], willChangeCount: 0, didChangeCount: 0)
        
        let removal = observer.observe(mapped.signal)
        verify(value: false, changes: [false], willChangeCount: 2, didChangeCount: 2)
        
        property1.change(true, transient: false)
        verify(value: false, changes: [false], willChangeCount: 3, didChangeCount: 3)
        
        property2.change(true, transient: false)
        verify(value: true, changes: [false, true], willChangeCount: 4, didChangeCount: 4)
        
        property2.change(false, transient: false)
        verify(value: false, changes: [false, true, false], willChangeCount: 5, didChangeCount: 5)
        
        property1.change(false, transient: false)
        verify(value: false, changes: [false, true, false], willChangeCount: 6, didChangeCount: 6)
        
        removal()
    }

    func testEq() {
        let property1 = mutableValueProperty(0)
        let property2 = mutableValueProperty(1)
        let mapped = property1 *== property2
        let observer = BoolObserver()

        func verify(value: Bool, changes: [Bool], willChangeCount: Int, didChangeCount: Int, file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(mapped.value, value, file: file, line: line)
            XCTAssertEqual(observer.changes, changes, file: file, line: line)
            XCTAssertEqual(observer.willChangeCount, willChangeCount, file: file, line: line)
            XCTAssertEqual(observer.didChangeCount, didChangeCount, file: file, line: line)
        }
        
        verify(value: false, changes: [], willChangeCount: 0, didChangeCount: 0)
        
        let removal = observer.observe(mapped.signal)
        verify(value: false, changes: [false], willChangeCount: 2, didChangeCount: 2)
        
        property1.change(2, transient: false)
        verify(value: false, changes: [false], willChangeCount: 3, didChangeCount: 3)
        
        property2.change(2, transient: false)
        verify(value: true, changes: [false, true], willChangeCount: 4, didChangeCount: 4)
        
        property2.change(3, transient: false)
        verify(value: false, changes: [false, true, false], willChangeCount: 5, didChangeCount: 5)
        
        property1.change(4, transient: false)
        verify(value: false, changes: [false, true, false], willChangeCount: 6, didChangeCount: 6)
        
        removal()
    }
}
