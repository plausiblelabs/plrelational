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
        
        set.update(binding1, newValue: "Hallo")
        
        XCTAssertEqual(binding1Values, ["Hello", "Hallo"])
        XCTAssertEqual(binding2Values, ["there"])
        XCTAssertEqual(binding1Detached, false)
        XCTAssertEqual(binding2Detached, false)
        
        set.update(binding2, newValue: "thar")
        
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
        var bindings: BindingSet! = BindingSet()
        
        let boolBinding = BidiValueBinding(false)
        let stringBinding = BidiValueBinding("")
        let intBinding = BidiValueBinding(6)
       
//        var boolValues: [Bool] = []
//        var stringValues: [String] = []
//        var intValues: [Int] = []

        XCTAssertEqual(boolBinding.value, false)
        XCTAssertEqual(stringBinding.value, "")
        XCTAssertEqual(intBinding.value, 6)
        
        XCTAssertEqual(boolBinding.observerCount, 0)
        XCTAssertEqual(stringBinding.observerCount, 0)
        XCTAssertEqual(intBinding.observerCount, 0)

        // We set up the connections such that `boolBinding` is the "master" value and the others
        // are secondary:
        //   - If `boolBinding` is updated, then `stringBinding` and `intBinding` are updated.
        //   - If `stringBinding` is updated, then `boolBinding` is updated, and `intBinding` should
        //     but updated transitively.
        //   - If `intBinding` is updated, then `boolBinding` is updated, and `stringBinding` should
        //     but updated transitively.
        
        // For this reverse case, we won't update the master value if the string is not "true" or "false"
        // (just to exercise the .NoChange case)
        bindings.connect(
            "boolBinding", boolBinding,
            "stringBinding", stringBinding,
            forward: {
                // Bool -> String
                .Change($0.description)
            },
            reverse: {
                // String -> Bool
                switch $0 {
                case "true":
                    return .Change(true)
                case "false":
                    return .Change(false)
                default:
                    return .NoChange
                }
            }
        )
        
        XCTAssertEqual(boolBinding.value, false)
        XCTAssertEqual(stringBinding.value, "false")
        XCTAssertEqual(intBinding.value, 6)
        
        XCTAssertEqual(boolBinding.observerCount, 1)
        XCTAssertEqual(stringBinding.observerCount, 1)
        XCTAssertEqual(intBinding.observerCount, 0)
        
        // For this reverse case, we'll treat any non-zero value as true
        bindings.connect(
            "boolBinding", boolBinding,
            "intBinding", intBinding,
            forward: {
                // Bool -> Int
                .Change($0 ? 1 : 0)
            },
            reverse: {
                // Int -> Bool
                .Change($0 != 0)
            }
        )
        
        XCTAssertEqual(boolBinding.value, false)
        XCTAssertEqual(stringBinding.value, "false")
        XCTAssertEqual(intBinding.value, 0)
        
        XCTAssertEqual(boolBinding.observerCount, 2)
        XCTAssertEqual(stringBinding.observerCount, 1)
        XCTAssertEqual(intBinding.observerCount, 1)

        // Update boolBinding and verify that secondary ones are updated
        bindings.update(boolBinding, newValue: true)
        
        XCTAssertEqual(boolBinding.value, true)
        XCTAssertEqual(stringBinding.value, "true")
        XCTAssertEqual(intBinding.value, 1)
        
        // Update stringBinding and verify that others are updated
        bindings.update(stringBinding, newValue: "false")
        
        XCTAssertEqual(boolBinding.value, false)
        XCTAssertEqual(stringBinding.value, "false")
        XCTAssertEqual(intBinding.value, 0)
        
        // Update stringBinding and verify that there is no change reported
        // TODO: Verify the no change part
        bindings.update(stringBinding, newValue: "false")
        
        XCTAssertEqual(boolBinding.value, false)
        XCTAssertEqual(stringBinding.value, "false")
        XCTAssertEqual(intBinding.value, 0)
        
        // Update intBinding and verify that others are updated
        bindings.update(intBinding, newValue: 8)
        
        XCTAssertEqual(boolBinding.value, true)
        XCTAssertEqual(stringBinding.value, "true")
        XCTAssertEqual(intBinding.value, 8)
        
        // Update stringBinding with an unknown value and verify that others are not updated
        bindings.update(stringBinding, newValue: "foo")
        
        XCTAssertEqual(boolBinding.value, true)
        XCTAssertEqual(stringBinding.value, "foo")
        XCTAssertEqual(intBinding.value, 8)
        
        // Update stringBinding with an known value and verify that others are updated
        bindings.update(stringBinding, newValue: "false")
        
        XCTAssertEqual(boolBinding.value, false)
        XCTAssertEqual(stringBinding.value, "false")
        XCTAssertEqual(intBinding.value, 0)
        
        bindings = nil
        
        XCTAssertEqual(boolBinding.observerCount, 0)
        XCTAssertEqual(stringBinding.observerCount, 0)
        XCTAssertEqual(intBinding.observerCount, 0)
    }
}
