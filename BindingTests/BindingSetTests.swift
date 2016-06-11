//
//  BindingSetTests.swift
//  Relational
//
//  Created by Chris Campbell on 6/8/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import XCTest
@testable import Binding

class BindingSetTests: XCTestCase {
    
    func testRegister() {
        var set: BindingSet! = BindingSet()
        
        let binding1 = BidiValueBinding("Hello")
        let binding2 = BidiValueBinding("there")
        
        var binding1Values: [String] = []
        var binding2Values: [String] = []
        
        var binding1Detached = false
        var binding2Detached = false
        
        let metadata = ChangeMetadata(transient: false)

        XCTAssertEqual(binding1Values, [])
        XCTAssertEqual(binding2Values, [])
        XCTAssertEqual(binding1Detached, false)
        XCTAssertEqual(binding2Detached, false)
        XCTAssertEqual(binding1.observerCount, 0)
        XCTAssertEqual(binding2.observerCount, 0)
        
        set.register("1", binding1, { binding1Values.append($0) }, onDetach: { binding1Detached = true })

        XCTAssertEqual(binding1Values, ["Hello"])
        XCTAssertEqual(binding2Values, [])
        XCTAssertEqual(binding1Detached, false)
        XCTAssertEqual(binding2Detached, false)
        XCTAssertEqual(binding1.observerCount, 1)
        XCTAssertEqual(binding2.observerCount, 0)

        set.register("2", binding2, { binding2Values.append($0) }, onDetach: { binding2Detached = true })
        
        XCTAssertEqual(binding1Values, ["Hello"])
        XCTAssertEqual(binding2Values, ["there"])
        XCTAssertEqual(binding1Detached, false)
        XCTAssertEqual(binding2Detached, false)
        XCTAssertEqual(binding1.observerCount, 1)
        XCTAssertEqual(binding2.observerCount, 1)
        
        binding1.update("Hallo", metadata)
        
        XCTAssertEqual(binding1Values, ["Hello", "Hallo"])
        XCTAssertEqual(binding2Values, ["there"])
        XCTAssertEqual(binding1Detached, false)
        XCTAssertEqual(binding2Detached, false)
        
        binding2.update("thar", metadata)
        
        XCTAssertEqual(binding1Values, ["Hello", "Hallo"])
        XCTAssertEqual(binding2Values, ["there", "thar"])
        XCTAssertEqual(binding1Detached, false)
        XCTAssertEqual(binding2Detached, false)
        
        set.register("2", nil, { binding2Values.append($0) }, onDetach: { binding2Detached = true })
        
        XCTAssertEqual(binding1Values, ["Hello", "Hallo"])
        XCTAssertEqual(binding2Values, ["there", "thar"])
        XCTAssertEqual(binding1Detached, false)
        XCTAssertEqual(binding2Detached, true)
        XCTAssertEqual(binding1.observerCount, 1)
        XCTAssertEqual(binding2.observerCount, 0)
        
        set = nil
        
        XCTAssertEqual(binding1Values, ["Hello", "Hallo"])
        XCTAssertEqual(binding2Values, ["there", "thar"])
        XCTAssertEqual(binding1Detached, false)
        XCTAssertEqual(binding2Detached, true)
        XCTAssertEqual(binding1.observerCount, 0)
        XCTAssertEqual(binding2.observerCount, 0)
    }
    
    func testConnect() {
        // TODO
    }
}