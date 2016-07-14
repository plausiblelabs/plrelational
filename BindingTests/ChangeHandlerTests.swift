//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
@testable import Binding

class ChangeHandlerTests: BindingTestCase {
    
    func testBasic() {
        var lockCount = 0
        var unlockCount = 0
        
        let handler = ChangeHandler(onLock: { lockCount += 1 }, onUnlock: { unlockCount += 1 })
        XCTAssertEqual(lockCount, 0)
        XCTAssertEqual(unlockCount, 0)
        
        handler.willChange()
        XCTAssertEqual(lockCount, 1)
        XCTAssertEqual(unlockCount, 0)
        
        handler.willChange()
        XCTAssertEqual(lockCount, 1)
        XCTAssertEqual(unlockCount, 0)
        
        handler.didChange()
        XCTAssertEqual(lockCount, 1)
        XCTAssertEqual(unlockCount, 0)
        
        handler.didChange()
        XCTAssertEqual(lockCount, 1)
        XCTAssertEqual(unlockCount, 1)

        handler.incrementCount(3)
        XCTAssertEqual(lockCount, 2)
        XCTAssertEqual(unlockCount, 1)
        
        handler.didChange()
        XCTAssertEqual(lockCount, 2)
        XCTAssertEqual(unlockCount, 1)
        
        handler.decrementCount(2)
        XCTAssertEqual(lockCount, 2)
        XCTAssertEqual(unlockCount, 2)
    }
}
