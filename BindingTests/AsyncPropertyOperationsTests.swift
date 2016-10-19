//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
@testable import Binding

class AsyncPropertyOperationsTests: BindingTestCase {
    
    func testMap() {
        let (signal, notify) = Signal<Bool>.pipe(initialValue: false)
        let property = AsyncReadableProperty(initialValue: false, signal: signal)
        let mapped = property.map{ $0 ? 1 : 0 }
        var changeObserved = false
        _ = mapped.signal.observe({ _ in changeObserved = true })
        mapped.start()
        
        XCTAssertEqual(mapped.value, 0)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        notify.valueChanging(true, transient: false)
        XCTAssertEqual(mapped.value, 1)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        // TODO: Need to pass isRepeat func to pipe() so that we can avoid duplicates
//        notify.valueChanging(true, transient: false)
//        XCTAssertEqual(mapped.value, 1)
//        XCTAssertEqual(changeObserved, false)
//        changeObserved = false
        
        notify.valueChanging(false, transient: false)
        XCTAssertEqual(mapped.value, 0)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
    }
    
    func testZip() {
        // TODO
    }
}
