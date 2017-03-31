//
//  InternedUTF8StringTests.swift
//  PLRelational
//
//  Created by Mike Ash on 3/31/17.
//  Copyright © 2017 mikeash. All rights reserved.
//

import XCTest
import PLRelational

class InternedUTF8StringTests: XCTestCase {
    func testAll() {
        let abc = InternedUTF8String.get("abc")
        XCTAssertEqual(abc, InternedUTF8String.get("abc"))
        
        let def = InternedUTF8String.get("def")
        XCTAssertEqual(def, InternedUTF8String.get("def"))
        
        XCTAssertNotEqual(abc, def)
        XCTAssertTrue(abc < def)
        XCTAssertFalse(abc > def)
        XCTAssertEqual(abc.string, "abc")
        XCTAssertEqual(def.string, "def")
    }
}
