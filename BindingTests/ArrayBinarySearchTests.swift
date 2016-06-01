//
//  ArrayBinarySearchTests.swift
//  Relational
//
//  Created by Chris Campbell on 5/12/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import XCTest
@testable import Binding

class ArrayBinarySearchTests: XCTestCase {
    
    func testBinarySearch() {
        XCTAssertEqual([].binarySearch(42), 0)
        XCTAssertEqual([0, 2, 4, 6].binarySearch(-1), 0)
        XCTAssertEqual([0, 2, 4, 6].binarySearch(0), 0)
        XCTAssertEqual([0, 2, 4, 6].binarySearch(1), 1)
        XCTAssertEqual([0, 2, 4, 6].binarySearch(2), 1)
        XCTAssertEqual([0, 2, 4, 6].binarySearch(3), 2)
        XCTAssertEqual([0, 2, 4, 6].binarySearch(4), 2)
        XCTAssertEqual([0, 2, 4, 6].binarySearch(5), 3)
        XCTAssertEqual([0, 2, 4, 6].binarySearch(6), 3)
        XCTAssertEqual([0, 2, 4, 6].binarySearch(7), 4)
        XCTAssertEqual([0, 2, 4, 6].binarySearch(8), 4)
    }
    
    func testInsertSorted() {

        func insert(v: Int, _ vs: [Int], _ expected: [Int], _ expectedIndex: Int) {
            var mutvs = vs
            let index = mutvs.insertSorted(v, { $0 })
            XCTAssertEqual(mutvs, expected)
            XCTAssertEqual(index, expectedIndex)
        }
        
        insert(42, [], [42], 0)
        insert(-1, [0, 2, 4, 6], [-1, 0, 2, 4, 6], 0)
        insert( 0, [0, 2, 4, 6], [0, 0, 2, 4, 6], 0)
        insert( 1, [0, 2, 4, 6], [0, 1, 2, 4, 6], 1)
        insert( 2, [0, 2, 4, 6], [0, 2, 2, 4, 6], 1)
        insert( 3, [0, 2, 4, 6], [0, 2, 3, 4, 6], 2)
        insert( 4, [0, 2, 4, 6], [0, 2, 4, 4, 6], 2)
        insert( 5, [0, 2, 4, 6], [0, 2, 4, 5, 6], 3)
        insert( 6, [0, 2, 4, 6], [0, 2, 4, 6, 6], 3)
        insert( 7, [0, 2, 4, 6], [0, 2, 4, 6, 7], 4)
        insert( 8, [0, 2, 4, 6], [0, 2, 4, 6, 8], 4)
    }
}
