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

        func verify(value: Int, changes: [Int], willChangeCount: Int = 0, didChangeCount: Int = 0, file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(mapped.value, value, file: file, line: line)
            XCTAssertEqual(observer.changes, changes, file: file, line: line)
            XCTAssertEqual(observer.willChangeCount, willChangeCount, file: file, line: line)
            XCTAssertEqual(observer.didChangeCount, didChangeCount, file: file, line: line)
        }

        verify(value: 0, changes: [])

        let removal = observer.observe(mapped.signal)
        verify(value: 0, changes: [0])

        property.change(true, transient: false)
        verify(value: 1, changes: [0, 1])

        property.change(true, transient: false)
        verify(value: 1, changes: [0, 1])

        property.change(false, transient: false)
        verify(value: 0, changes: [0, 1, 0])
        
        removal()
    }
    
    func testMapLifetime() {
        let property = mutableValueProperty(false)
        var mapped: ReadableProperty<Int>? = property.map{ $0 ? 1 : 0 }
        weak var weakMapped: ReadableProperty<Int>? = mapped
        
        XCTAssertNotNil(weakMapped)
        XCTAssertEqual(weakMapped!.value, 0)
        
        property.change(true)
        XCTAssertEqual(weakMapped!.value, 1)
        
        // Verify that property weakly observes its underlying signal and does not leave dangling strong references
        // that prevent the property from being deinitialized
        mapped = nil
        XCTAssertNil(weakMapped)
    }

    func testZip() {
        let property1 = mutableValueProperty(false)
        let property2 = mutableValueProperty(false)
        let zipped = zip(property1, property2)
        let observer = TestObserver<(Bool, Bool)>()
        
        func verify(value: (Bool, Bool), changes: [(Bool, Bool)], willChangeCount: Int = 0, didChangeCount: Int = 0, file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(zipped.value.0, value.0, file: file, line: line)
            XCTAssertEqual(zipped.value.1, value.1, file: file, line: line)
            XCTAssertEqual(observer.changes.map{ $0.0 }, changes.map{ $0.0 }, file: file, line: line)
            XCTAssertEqual(observer.changes.map{ $0.1 }, changes.map{ $0.1 }, file: file, line: line)
            XCTAssertEqual(observer.willChangeCount, willChangeCount, file: file, line: line)
            XCTAssertEqual(observer.didChangeCount, didChangeCount, file: file, line: line)
        }
        
        verify(value: (false, false), changes: [])
        
        let removal = observer.observe(zipped.signal)
        verify(value: (false, false), changes: [(false, false)])

        property1.change(true, transient: false)
        verify(value: (true, false), changes: [(false, false), (true, false)])

        property2.change(true, transient: false)
        verify(value: (true, true), changes: [(false, false), (true, false), (true, true)])

        property2.change(true, transient: false)
        verify(value: (true, true), changes: [(false, false), (true, false), (true, true)])
        
        removal()
    }
    
    func testZipLifetime() {
        let property1 = mutableValueProperty(false)
        let property2 = mutableValueProperty(false)
        var zipped: ReadableProperty<(Bool, Bool)>? = zip(property1, property2)
        weak var weakZipped: ReadableProperty<(Bool, Bool)>? = zipped
        
        XCTAssertNotNil(weakZipped)
        XCTAssertEqual(weakZipped!.value.0, false)
        XCTAssertEqual(weakZipped!.value.1, false)
        
        property2.change(true)
        XCTAssertEqual(weakZipped!.value.0, false)
        XCTAssertEqual(weakZipped!.value.1, true)
        
        // Verify that property weakly observes its underlying signal and does not leave dangling strong references
        // that prevent the property from being deinitialized
        zipped = nil
        XCTAssertNil(weakZipped)
    }
    
    func testZipAndMapLifetime() {
        let property1 = mutableValueProperty(false)
        let property2 = mutableValueProperty(false)

        var mapped: ReadableProperty<String>? =
            zip(property1, property2)
                .map{ "\($0.0) \($0.1)" }
        weak var weakMapped: ReadableProperty<String>? = mapped
        
        XCTAssertNotNil(weakMapped)
        XCTAssertEqual(weakMapped!.value, "false false")

        property2.change(true)
        XCTAssertEqual(weakMapped!.value, "false true")
        
        // Verify that property weakly observes its underlying signal and does not leave dangling strong references
        // that prevent the property from being deinitialized
        mapped = nil
        XCTAssertNil(weakMapped)
    }
    
    func testNot() {
        let property = mutableValueProperty(false)
        let mapped = not(property)
        let observer = BoolObserver()
        
        func verify(value: Bool, changes: [Bool], willChangeCount: Int = 0, didChangeCount: Int = 0, file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(mapped.value, value, file: file, line: line)
            XCTAssertEqual(observer.changes, changes, file: file, line: line)
            XCTAssertEqual(observer.willChangeCount, willChangeCount, file: file, line: line)
            XCTAssertEqual(observer.didChangeCount, didChangeCount, file: file, line: line)
        }
        
        verify(value: true, changes: [])
        
        let removal = observer.observe(mapped.signal)
        verify(value: true, changes: [true])
        
        property.change(true, transient: false)
        verify(value: false, changes: [true, false])
        
        property.change(true, transient: false)
        verify(value: false, changes: [true, false])
        
        property.change(false, transient: false)
        verify(value: true, changes: [true, false, true])
        
        removal()
    }

    func testOr() {
        let property1 = mutableValueProperty(false)
        let property2 = mutableValueProperty(false)
        let mapped = property1 *|| property2
        let observer = BoolObserver()
        
        func verify(value: Bool, changes: [Bool], willChangeCount: Int = 0, didChangeCount: Int = 0, file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(mapped.value, value, file: file, line: line)
            XCTAssertEqual(observer.changes, changes, file: file, line: line)
            XCTAssertEqual(observer.willChangeCount, willChangeCount, file: file, line: line)
            XCTAssertEqual(observer.didChangeCount, didChangeCount, file: file, line: line)
        }
        
        verify(value: false, changes: [])
        
        let removal = observer.observe(mapped.signal)
        verify(value: false, changes: [false])
        
        property1.change(true, transient: false)
        verify(value: true, changes: [false, true])

        property2.change(true, transient: false)
        verify(value: true, changes: [false, true])

        property2.change(false, transient: false)
        verify(value: true, changes: [false, true])

        property1.change(false, transient: false)
        verify(value: false, changes: [false, true, false])
        
        removal()
    }

    func testAnd() {
        let property1 = mutableValueProperty(false)
        let property2 = mutableValueProperty(false)
        let mapped = property1 *&& property2
        let observer = BoolObserver()
        
        func verify(value: Bool, changes: [Bool], willChangeCount: Int = 0, didChangeCount: Int = 0, file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(mapped.value, value, file: file, line: line)
            XCTAssertEqual(observer.changes, changes, file: file, line: line)
            XCTAssertEqual(observer.willChangeCount, willChangeCount, file: file, line: line)
            XCTAssertEqual(observer.didChangeCount, didChangeCount, file: file, line: line)
        }
        
        verify(value: false, changes: [])
        
        let removal = observer.observe(mapped.signal)
        verify(value: false, changes: [false])
        
        property1.change(true, transient: false)
        verify(value: false, changes: [false])
        
        property2.change(true, transient: false)
        verify(value: true, changes: [false, true])
        
        property2.change(false, transient: false)
        verify(value: false, changes: [false, true, false])
        
        property1.change(false, transient: false)
        verify(value: false, changes: [false, true, false])
        
        removal()
    }

    func testEq() {
        let property1 = mutableValueProperty(0)
        let property2 = mutableValueProperty(1)
        let mapped = property1 *== property2
        let observer = BoolObserver()

        func verify(value: Bool, changes: [Bool], willChangeCount: Int = 0, didChangeCount: Int = 0, file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(mapped.value, value, file: file, line: line)
            XCTAssertEqual(observer.changes, changes, file: file, line: line)
            XCTAssertEqual(observer.willChangeCount, willChangeCount, file: file, line: line)
            XCTAssertEqual(observer.didChangeCount, didChangeCount, file: file, line: line)
        }
        
        verify(value: false, changes: [])
        
        let removal = observer.observe(mapped.signal)
        verify(value: false, changes: [false])
        
        property1.change(2, transient: false)
        verify(value: false, changes: [false])
        
        property2.change(2, transient: false)
        verify(value: true, changes: [false, true])
        
        property2.change(3, transient: false)
        verify(value: false, changes: [false, true, false])
        
        property1.change(4, transient: false)
        verify(value: false, changes: [false, true, false])
        
        removal()
    }
}
