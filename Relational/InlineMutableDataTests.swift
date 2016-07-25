//
//  InlineMutableDataTests.swift
//  Relational
//
//  Created by Mike Ash on 7/25/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import XCTest
@testable import libRelational

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
        
        func assertContents(data: InlineMutableData) {
            XCTAssertEqual(data.length, bigArray.count)
            data.withUnsafeMutablePointerToElements({
                XCTAssertTrue(memcmp($0, bigArray, data.length) == 0)
            })
        }
        
        var a = InlineMutableData.make(10)
        InlineMutableData.append(&a, pointer: bigArray, length: bigArray.count)
        assertContents(a)
        
        var b = InlineMutableData.make(bigArray.count)
        InlineMutableData.append(&b, pointer: bigArray, length: bigArray.count)
        assertContents(b)
        
        var c = InlineMutableData.make(10)
        for elt in bigArray {
            var elt = elt
            InlineMutableData.append(&c, pointer: &elt, length: 1)
        }
        assertContents(c)
        
        var d = InlineMutableData.make(10)
        for elt in bigArray {
            var elt = elt
            InlineMutableData.append(&d, pointer: &elt, length: 1)
        }
        assertContents(d)
        
        XCTAssertEqual(a, b)
        XCTAssertEqual(a, c)
        XCTAssertEqual(a, d)
    }
}
