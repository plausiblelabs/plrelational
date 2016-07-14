//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
@testable import Binding

class SignalOperationsTests: BindingTestCase {
    
    func testMap() {
        let (signal, notify) = Signal<Bool>.pipe()
        let mapped = signal.map{ $0 ? 1 : 0 }
        
        var mappedValue: Int?
        var willChangeCount = 0
        var changingCount = 0
        var didChangeCount = 0
        
        _ = mapped.observe(SignalObserver(
            valueWillChange: { willChangeCount += 1 },
            valueChanging: { newValue, _ in
                changingCount = mapped.changeCount
                mappedValue = newValue
            },
            valueDidChange: { didChangeCount += 1 }
        ))

        XCTAssertEqual(mappedValue, nil)
        XCTAssertEqual(willChangeCount, 0)
        XCTAssertEqual(didChangeCount, 0)
        XCTAssertEqual(changingCount, 0)
        XCTAssertEqual(mapped.changeCount, 0)

        notify.valueWillChange()
        notify.valueChanging(true)
        notify.valueDidChange()
        XCTAssertEqual(mappedValue, 1)
        XCTAssertEqual(willChangeCount, 1)
        XCTAssertEqual(didChangeCount, 1)
        XCTAssertEqual(changingCount, 1)
        XCTAssertEqual(mapped.changeCount, 0)
        
        notify.valueWillChange()
        notify.valueChanging(false)
        notify.valueDidChange()
        XCTAssertEqual(mappedValue, 0)
        XCTAssertEqual(willChangeCount, 2)
        XCTAssertEqual(didChangeCount, 2)
        XCTAssertEqual(changingCount, 1)
        XCTAssertEqual(mapped.changeCount, 0)
    }
    
    func testZip() {
        let (signal1, notify1) = Signal<Bool>.pipe()
        let (signal2, notify2) = Signal<Bool>.pipe()
        let zipped = zip(signal1, signal2)
        var zippedValue: (Bool, Bool)?
        
        _ = zipped.observe({ newValue, _ in zippedValue = newValue })
        XCTAssertEqual(zippedValue?.0, nil)
        XCTAssertEqual(zippedValue?.1, nil)

        notify1.valueChanging(false)
        XCTAssertEqual(zippedValue?.0, nil)
        XCTAssertEqual(zippedValue?.1, nil)

        notify2.valueChanging(true)
        XCTAssertEqual(zippedValue?.0, false)
        XCTAssertEqual(zippedValue?.1, true)
        
        notify1.valueChanging(true)
        XCTAssertEqual(zippedValue?.0, true)
        XCTAssertEqual(zippedValue?.1, true)
    }
}
