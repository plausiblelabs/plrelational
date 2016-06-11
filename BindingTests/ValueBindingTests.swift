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
    
    func testMap() {
        let binding = BidiValueBinding(false)
        let mapped = binding.map{ $0 ? 1 : 0 }
        var changed = false
        _ = mapped.addChangeObserver({ _ in changed = true })
        let metadata = ChangeMetadata(transient: false)
        
        XCTAssertEqual(mapped.value, 0)
        XCTAssertEqual(changed, false)
        changed = false

        binding.update(true, metadata)
        XCTAssertEqual(mapped.value, 1)
        XCTAssertEqual(changed, true)
        changed = false
        
        binding.update(true, metadata)
        XCTAssertEqual(mapped.value, 1)
        XCTAssertEqual(changed, false)
        changed = false
        
        binding.update(false, metadata)
        XCTAssertEqual(mapped.value, 0)
        XCTAssertEqual(changed, true)
        changed = false
    }
    
    func testZip() {
        let binding1 = BidiValueBinding(false)
        let binding2 = BidiValueBinding(false)
        let zipped = binding1.zip(binding2)
        var changed = false
        _ = zipped.addChangeObserver({ _ in changed = true })
        let metadata = ChangeMetadata(transient: false)

        XCTAssertEqual(zipped.value.0, false)
        XCTAssertEqual(zipped.value.1, false)
        XCTAssertEqual(changed, false)
        changed = false
        
        binding1.update(true, metadata)
        XCTAssertEqual(zipped.value.0, true)
        XCTAssertEqual(zipped.value.1, false)
        XCTAssertEqual(changed, true)
        changed = false
        
        binding2.update(true, metadata)
        XCTAssertEqual(zipped.value.0, true)
        XCTAssertEqual(zipped.value.1, true)
        XCTAssertEqual(changed, true)
        changed = false
        
        binding2.update(true, metadata)
        XCTAssertEqual(zipped.value.0, true)
        XCTAssertEqual(zipped.value.1, true)
        XCTAssertEqual(changed, false)
        changed = false
    }
    
    func testBidiBoolBinding() {
        let binding = BidiValueBinding(false)
        var changed = false
        _ = binding.addChangeObserver({ _ in changed = true })
        let metadata = ChangeMetadata(transient: false)

        XCTAssertEqual(binding.value, false)
        XCTAssertEqual(changed, false)
        changed = false

        binding.toggle(metadata)
        XCTAssertEqual(binding.value, true)
        XCTAssertEqual(changed, true)
        changed = false

        binding.toggle(metadata)
        XCTAssertEqual(binding.value, false)
        XCTAssertEqual(changed, true)
        changed = false

        binding.update(true, metadata)
        XCTAssertEqual(binding.value, true)
        XCTAssertEqual(changed, true)
        changed = false

        binding.update(true, metadata)
        XCTAssertEqual(binding.value, true)
        XCTAssertEqual(changed, false)
        changed = false
    }
}
