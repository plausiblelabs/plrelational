//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
@testable import PLRelational

class InlineMutableDataTests: XCTestCase {
    func testBigData() {
        var bigArray: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
        bigArray += bigArray
        bigArray += bigArray
        bigArray += bigArray
        bigArray += bigArray
        bigArray += bigArray
        bigArray += bigArray
        bigArray += bigArray
        bigArray += bigArray
        bigArray += bigArray
        bigArray += bigArray
        
        func assertContents(_ data: InlineMutableData) {
            XCTAssertEqual(data.length, bigArray.count)
            data.withUnsafeMutablePointerToElements({
                XCTAssertTrue(memcmp($0, bigArray, data.length) == 0)
            })
        }
        
        var a = InlineMutableData.make(10)
        a = InlineMutableData.append(a, pointer: bigArray, length: bigArray.count)
        assertContents(a)
        
        var b = InlineMutableData.make(bigArray.count)
        b = InlineMutableData.append(b, pointer: bigArray, length: bigArray.count)
        assertContents(b)
        
        var c = InlineMutableData.make(10)
        for elt in bigArray {
            var elt = elt
            c = InlineMutableData.append(c, pointer: &elt, length: 1)
        }
        assertContents(c)
        
        var d = InlineMutableData.make(10)
        for elt in bigArray {
            var elt = elt
            d = InlineMutableData.append(d, pointer: &elt, length: 1)
        }
        assertContents(d)
        
        XCTAssertEqual(a, b)
        XCTAssertEqual(a, c)
        XCTAssertEqual(a, d)
    }
}
