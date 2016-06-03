//
//  ValueBindingTests.swift
//  Relational
//
//  Created by Chris Campbell on 6/3/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import XCTest
@testable import Binding

class ValueBindingTests: BindingTestCase {
    
    func testBidiBoolBinding() {
        let binding = BidiValueBinding(initialValue: false)
        var changed = false
        _ = binding.addChangeObserver({ _ in changed = true })
        
        XCTAssertEqual(binding.value, false)
        XCTAssertEqual(changed, false)
        changed = false

        binding.toggle()
        XCTAssertEqual(binding.value, true)
        XCTAssertEqual(changed, true)
        changed = false

        binding.toggle()
        XCTAssertEqual(binding.value, false)
        XCTAssertEqual(changed, true)
        changed = false

        binding.commit(true)
        XCTAssertEqual(binding.value, true)
        XCTAssertEqual(changed, true)
        changed = false

        binding.commit(true)
        XCTAssertEqual(binding.value, true)
        // TODO: Verify that change observers aren't notified when value isn't changing
        //XCTAssertEqual(changed, false)
        changed = false
    }
}
