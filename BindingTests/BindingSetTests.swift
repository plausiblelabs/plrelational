//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
@testable import Binding

class BindingSetTests: XCTestCase {
    
    func testObserve() {
        var set: BindingSet! = BindingSet()
        
        let observable1 = mutableObservableValue("Hello")
        let observable2 = mutableObservableValue("there")
        
        var observable1Values: [String] = []
        var observable2Values: [String] = []
        
        var observable1Detached = false
        var observable2Detached = false
        
        XCTAssertEqual(observable1Values, [])
        XCTAssertEqual(observable2Values, [])
        XCTAssertEqual(observable1Detached, false)
        XCTAssertEqual(observable2Detached, false)
        XCTAssertEqual(observable1.observerCount, 0)
        XCTAssertEqual(observable2.observerCount, 0)
        
        set.observe(observable1, "1", { observable1Values.append($0) }, onDetach: { observable1Detached = true })

        XCTAssertEqual(observable1Values, ["Hello"])
        XCTAssertEqual(observable2Values, [])
        XCTAssertEqual(observable1Detached, false)
        XCTAssertEqual(observable2Detached, false)
        XCTAssertEqual(observable1.observerCount, 1)
        XCTAssertEqual(observable2.observerCount, 0)

        set.observe(observable2, "2", { observable2Values.append($0) }, onDetach: { observable2Detached = true })
        
        XCTAssertEqual(observable1Values, ["Hello"])
        XCTAssertEqual(observable2Values, ["there"])
        XCTAssertEqual(observable1Detached, false)
        XCTAssertEqual(observable2Detached, false)
        XCTAssertEqual(observable1.observerCount, 1)
        XCTAssertEqual(observable2.observerCount, 1)
        
        // Simulate observable1's value being updated externally (i.e., not through BindingSet.update, which
        // has self-initiated change protection) and verify that the onValue callback is called with the
        // new value
        observable1.update("Hallo", ChangeMetadata(transient: false))
        
        XCTAssertEqual(observable1Values, ["Hello", "Hallo"])
        XCTAssertEqual(observable2Values, ["there"])
        XCTAssertEqual(observable1Detached, false)
        XCTAssertEqual(observable2Detached, false)

        // Simulate observable2's value being updated internally (i.e., via BindingSet.update, which suppresses
        // the onValue call, so that the new value is not appended to observable2Values)
        set.update(observable2, newValue: "thar")
        
        XCTAssertEqual(observable1Values, ["Hello", "Hallo"])
        XCTAssertEqual(observable2Values, ["there"])
        XCTAssertEqual(observable1Detached, false)
        XCTAssertEqual(observable2Detached, false)
        
        set.observe(nil, "2", { observable2Values.append($0) }, onDetach: { observable2Detached = true })
        
        XCTAssertEqual(observable1Values, ["Hello", "Hallo"])
        XCTAssertEqual(observable2Values, ["there"])
        XCTAssertEqual(observable1Detached, false)
        XCTAssertEqual(observable2Detached, true)
        XCTAssertEqual(observable1.observerCount, 1)
        XCTAssertEqual(observable2.observerCount, 0)
        
        set = nil
        
        XCTAssertEqual(observable1Values, ["Hello", "Hallo"])
        XCTAssertEqual(observable2Values, ["there"])
        XCTAssertEqual(observable1Detached, false)
        XCTAssertEqual(observable2Detached, true)
        XCTAssertEqual(observable1.observerCount, 0)
        XCTAssertEqual(observable2.observerCount, 0)
    }
    
    func testConnect() {
        var set: BindingSet! = BindingSet()
        
        let mutableBool = mutableObservableValue(false)
        let mutableString = mutableObservableValue("")
        let mutableInt = mutableObservableValue(6)
       
        XCTAssertEqual(mutableBool.value, false)
        XCTAssertEqual(mutableString.value, "")
        XCTAssertEqual(mutableInt.value, 6)
        
        XCTAssertEqual(mutableBool.observerCount, 0)
        XCTAssertEqual(mutableString.observerCount, 0)
        XCTAssertEqual(mutableInt.observerCount, 0)

        // We set up the connections such that `mutableBool` is the "master" value and the others
        // are secondary:
        //   - If `mutableBool` is updated, then `mutableString` and `mutableInt` are updated.
        //   - If `mutableString` is updated, then `mutableBool` is updated, and `mutableInt` should
        //     but updated transitively.
        //   - If `mutableInt` is updated, then `mutableBool` is updated, and `mutableString` should
        //     but updated transitively.
        
        // For this reverse case, we won't update the master value if the string is not "true" or "false"
        // (just to exercise the .NoChange case)
        set.connect(
            mutableBool, "mutableBool",
            mutableString, "mutableString",
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
        
        XCTAssertEqual(mutableBool.value, false)
        XCTAssertEqual(mutableString.value, "false")
        XCTAssertEqual(mutableInt.value, 6)
        
        XCTAssertEqual(mutableBool.observerCount, 1)
        XCTAssertEqual(mutableString.observerCount, 1)
        XCTAssertEqual(mutableInt.observerCount, 0)
        
        // For this reverse case, we'll treat any non-zero value as true
        set.connect(
            mutableBool, "mutableBool",
            mutableInt, "mutableInt",
            forward: {
                // Bool -> Int
                .Change($0 ? 1 : 0)
            },
            reverse: {
                // Int -> Bool
                .Change($0 != 0)
            }
        )
        
        XCTAssertEqual(mutableBool.value, false)
        XCTAssertEqual(mutableString.value, "false")
        XCTAssertEqual(mutableInt.value, 0)
        
        XCTAssertEqual(mutableBool.observerCount, 2)
        XCTAssertEqual(mutableString.observerCount, 1)
        XCTAssertEqual(mutableInt.observerCount, 1)

        // Update mutableBool and verify that secondary ones are updated
        set.update(mutableBool, newValue: true)
        
        XCTAssertEqual(mutableBool.value, true)
        XCTAssertEqual(mutableString.value, "true")
        XCTAssertEqual(mutableInt.value, 1)
        
        // Update mutableString and verify that others are updated
        set.update(mutableString, newValue: "false")
        
        XCTAssertEqual(mutableBool.value, false)
        XCTAssertEqual(mutableString.value, "false")
        XCTAssertEqual(mutableInt.value, 0)
        
        // Update mutableString and verify that there is no change reported
        // TODO: Verify the no change part
        set.update(mutableString, newValue: "false")
        
        XCTAssertEqual(mutableBool.value, false)
        XCTAssertEqual(mutableString.value, "false")
        XCTAssertEqual(mutableInt.value, 0)
        
        // Update mutableInt and verify that others are updated
        set.update(mutableInt, newValue: 8)
        
        XCTAssertEqual(mutableBool.value, true)
        XCTAssertEqual(mutableString.value, "true")
        XCTAssertEqual(mutableInt.value, 8)
        
        // Update mutableString with an unknown value and verify that others are not updated
        set.update(mutableString, newValue: "foo")
        
        XCTAssertEqual(mutableBool.value, true)
        XCTAssertEqual(mutableString.value, "foo")
        XCTAssertEqual(mutableInt.value, 8)
        
        // Update mutableString with an known value and verify that others are updated
        set.update(mutableString, newValue: "false")
        
        XCTAssertEqual(mutableBool.value, false)
        XCTAssertEqual(mutableString.value, "false")
        XCTAssertEqual(mutableInt.value, 0)
        
        set = nil
        
        XCTAssertEqual(mutableBool.observerCount, 0)
        XCTAssertEqual(mutableString.observerCount, 0)
        XCTAssertEqual(mutableInt.observerCount, 0)
    }
}
