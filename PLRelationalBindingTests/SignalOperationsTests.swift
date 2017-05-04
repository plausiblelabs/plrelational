//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
@testable import PLRelationalBinding

class TestObserver<T> {
    var willChangeCount = 0
    var didChangeCount = 0
    var changes: [T] = []
    
    func observe(_ signal: Signal<T>) -> ObserverRemoval {
        return signal.observe(SignalObserver(
            valueWillChange: {
                self.willChangeCount += 1
            },
            valueChanging: { newValue, _ in
                self.changes.append(newValue)
            },
            valueDidChange: {
                self.didChangeCount += 1
            }
        ))
    }
}

typealias StringObserver = TestObserver<String>
typealias BoolObserver = TestObserver<Bool>
typealias IntObserver = TestObserver<Int>

func verify<T: Equatable>(_ observer: TestObserver<T>, changes: [T], willChangeCount: Int, didChangeCount: Int, file: StaticString = #file, line: UInt = #line) {
    XCTAssertEqual(observer.changes, changes, file: file, line: line)
    XCTAssertEqual(observer.willChangeCount, willChangeCount, file: file, line: line)
    XCTAssertEqual(observer.didChangeCount, didChangeCount, file: file, line: line)
}

class SignalOperationsTests: BindingTestCase {
    
    private func verifyUnary<T, U: Equatable>(notify: Signal<T>.Notify, mapped: Signal<U>, values: [T], expected: [U], file: StaticString = #file, line: UInt = #line) {
        var mappedValue: U?
        var willChangeCount = 0
        var changingCount = 0
        var didChangeCount = 0
        
        _ = mapped.observe(SignalObserver(
            valueWillChange: { willChangeCount += 1 },
            valueChanging: { newValue, _ in
                changingCount += 1
                mappedValue = newValue
            },
            valueDidChange: { didChangeCount += 1 }
        ))
        
        XCTAssertEqual(mappedValue, nil)
        XCTAssertEqual(willChangeCount, 0)
        XCTAssertEqual(changingCount, 0)
        XCTAssertEqual(didChangeCount, 0)

        notify.valueWillChange()
        notify.valueChanging(values[0])
        notify.valueDidChange()
        XCTAssertEqual(mappedValue, expected[0])
        XCTAssertEqual(willChangeCount, 1)
        XCTAssertEqual(changingCount, 1)
        XCTAssertEqual(didChangeCount, 1)
        
        notify.valueWillChange()
        notify.valueChanging(values[1])
        notify.valueDidChange()
        XCTAssertEqual(mappedValue, expected[1])
        XCTAssertEqual(willChangeCount, 2)
        XCTAssertEqual(changingCount, 2)
        XCTAssertEqual(didChangeCount, 2)
    }
    
    private func verifyBinary<T1, T2, U: Equatable>(notify1: Signal<T1>.Notify, notify2: Signal<T2>.Notify, mapped: Signal<U>, values1: [T1], values2: [T2], expected: [U], file: StaticString = #file, line: UInt = #line) {
        var mappedValue: U?
        var willChangeCount = 0
        var changingCount = 0
        var didChangeCount = 0
        
        _ = mapped.observe(SignalObserver(
            valueWillChange: { willChangeCount += 1 },
            valueChanging: { newValue, _ in
                changingCount += 1
                mappedValue = newValue
            },
            valueDidChange: { didChangeCount += 1 }
        ))
        
        XCTAssertEqual(mappedValue, nil)
        XCTAssertEqual(willChangeCount, 0)
        XCTAssertEqual(didChangeCount, 0)
        XCTAssertEqual(changingCount, 0)
        
        notify1.valueWillChange()
        notify1.valueChanging(values1[0])
        notify1.valueDidChange()
        XCTAssertEqual(mappedValue, nil)
        XCTAssertEqual(willChangeCount, 1)
        XCTAssertEqual(didChangeCount, 1)
        XCTAssertEqual(changingCount, 0)

        notify2.valueWillChange()
        notify2.valueChanging(values2[0])
        notify2.valueDidChange()
        XCTAssertEqual(mappedValue, expected[0])
        XCTAssertEqual(willChangeCount, 2)
        XCTAssertEqual(didChangeCount, 2)
        XCTAssertEqual(changingCount, 1)
        
        notify1.valueWillChange()
        notify1.valueChanging(values1[1])
        notify1.valueDidChange()
        XCTAssertEqual(mappedValue, expected[1])
        XCTAssertEqual(willChangeCount, 3)
        XCTAssertEqual(didChangeCount, 3)
        XCTAssertEqual(changingCount, 2)
    }

    func testMap() {
        let (signal, notify) = Signal<Bool>.pipe()

        let mapped = signal.map{ $0 ? 1 : 0 }
        
        verifyUnary(
            notify: notify,
            mapped: mapped,
            values: [true, false],
            expected: [1, 0]
        )
    }
    
    func testZip() {
        let (signal1, notify1) = Signal<Bool>.pipe()
        let (signal2, notify2) = Signal<Bool>.pipe()
        
        let zipped = zip(signal1, signal2)

        // TODO: Can use verifyBinary() for this if we pass a custom equality checking function for tuples
        
        var zippedValue: (Bool, Bool)?
        var willChangeCount = 0
        var changingCount = 0
        var didChangeCount = 0
        
        _ = zipped.observe(SignalObserver(
            valueWillChange: { willChangeCount += 1 },
            valueChanging: { newValue, _ in
                changingCount += 1
                zippedValue = newValue
            },
            valueDidChange: { didChangeCount += 1 }
        ))

        XCTAssertEqual(zippedValue?.0, nil)
        XCTAssertEqual(zippedValue?.1, nil)
        XCTAssertEqual(willChangeCount, 0)
        XCTAssertEqual(didChangeCount, 0)
        XCTAssertEqual(changingCount, 0)

        notify1.valueWillChange()
        notify1.valueChanging(false)
        notify1.valueDidChange()
        XCTAssertEqual(zippedValue?.0, nil)
        XCTAssertEqual(zippedValue?.1, nil)
        XCTAssertEqual(willChangeCount, 1)
        XCTAssertEqual(didChangeCount, 1)
        XCTAssertEqual(changingCount, 0)

        notify2.valueWillChange()
        notify2.valueChanging(true)
        notify2.valueDidChange()
        XCTAssertEqual(zippedValue?.0, false)
        XCTAssertEqual(zippedValue?.1, true)
        XCTAssertEqual(willChangeCount, 2)
        XCTAssertEqual(didChangeCount, 2)
        XCTAssertEqual(changingCount, 1)

        notify1.valueWillChange()
        notify1.valueChanging(true)
        notify1.valueDidChange()
        XCTAssertEqual(zippedValue?.0, true)
        XCTAssertEqual(zippedValue?.1, true)
        XCTAssertEqual(willChangeCount, 3)
        XCTAssertEqual(didChangeCount, 3)
        XCTAssertEqual(changingCount, 2)
    }
    
    func testNot() {
        let (signal, notify) = Signal<Bool>.pipe()
        
        // Send a valueWillChange to the underlying signal to mimic the case where a signal
        // is mapped while already in a change block
        notify.valueWillChange()
        
        let mapped = not(signal)

        verifyUnary(
            notify: notify,
            mapped: mapped,
            values: [true, false],
            expected: [false, true]
        )
    }
    
    func testOr() {
        let (signal1, notify1) = Signal<Bool>.pipe()
        let (signal2, notify2) = Signal<Bool>.pipe()
        
        let mapped = signal1 *|| signal2

        verifyBinary(
            notify1: notify1,
            notify2: notify2,
            mapped: mapped,
            values1: [false, true],
            values2: [false],
            expected: [false, true]
        )
    }
    
    func testAnd() {
        let (signal1, notify1) = Signal<Bool>.pipe()
        let (signal2, notify2) = Signal<Bool>.pipe()
        
        let mapped = signal1 *&& signal2
        
        verifyBinary(
            notify1: notify1,
            notify2: notify2,
            mapped: mapped,
            values1: [false, true],
            values2: [true],
            expected: [false, true]
        )
    }

    func testThen() {
        var count = 0
        let (signal, notify) = Signal<Bool>.pipe()
        
        let then = signal.then{ count += 1 }
        
        _ = then.observe{ _ in }
        XCTAssertEqual(count, 0)
        
        notify.valueChanging(false)
        XCTAssertEqual(count, 0)
        
        notify.valueChanging(true)
        XCTAssertEqual(count, 1)
        
        notify.valueChanging(true)
        XCTAssertEqual(count, 2)
    }

    func testEq() {
        let (signal1, notify1) = Signal<Bool>.pipe()
        let (signal2, notify2) = Signal<Bool>.pipe()
        
        let mapped = signal1 *== signal2
        
        verifyBinary(
            notify1: notify1,
            notify2: notify2,
            mapped: mapped,
            values1: [false, true],
            values2: [true],
            expected: [false, true]
        )
    }
}
