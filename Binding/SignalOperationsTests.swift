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
        
        _ = mapped.observe({ newValue, _ in mappedValue = newValue })
        XCTAssertEqual(mappedValue, nil)

        notify.valueChanging(true)
        XCTAssertEqual(mappedValue, 1)
        
        notify.valueChanging(false)
        XCTAssertEqual(mappedValue, 0)
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
