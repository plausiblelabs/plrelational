//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
@testable import PLRelationalBinding

class AsyncPropertyTests: BindingTestCase {
    
    func testLiftSynchronousPropertyToAsync() {
        let syncProperty = mutableValueProperty("1")
        let asyncProperty = syncProperty.async()
        asyncProperty.start()
        XCTAssertEqual(syncProperty.value, "1")
        XCTAssertEqual(asyncProperty.value, "1")
        
        syncProperty.change("2", transient: false)
        XCTAssertEqual(syncProperty.value, "2")
        XCTAssertEqual(asyncProperty.value, "2")
    }
}
