//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
@testable import Binding

class PropertyTests: XCTestCase {
    
    func testBind() {
        var value: String = "initial property value"
        var values: [String] = []
        
        var property: ReadableProperty<String>! = ReadableProperty(
            get: { value },
            set: { newValue, _ in
                value = newValue
                values.append(newValue)
            }
        )
        
        // Create two observable values so that we can verify the case where a property is bound to
        // multiple signals at the same time
        let rhs1 = mutableObservableValue("initial rhs1 value")
        let rhs2 = mutableObservableValue("initial rhs2 value")

        // Verify the initial state
        XCTAssertEqual(property.get(), "initial property value")
        XCTAssertEqual(values, [])
        XCTAssertEqual(rhs1.observerCount, 0)
        XCTAssertEqual(rhs2.observerCount, 0)

        // Bind property to the first observable value
        let binding1 = property <~ rhs1
        XCTAssertEqual(property.get(), "initial rhs1 value")
        XCTAssertEqual(values, ["initial rhs1 value"])
        XCTAssertEqual(rhs1.observerCount, 1)
        XCTAssertEqual(rhs2.observerCount, 0)

        // Change the first observable value and verify that property's value is updated
        rhs1.update("rhs1 was updated", ChangeMetadata(transient: false))
        XCTAssertEqual(property.get(), "rhs1 was updated")
        XCTAssertEqual(values, ["initial rhs1 value", "rhs1 was updated"])
        XCTAssertEqual(rhs1.observerCount, 1)
        XCTAssertEqual(rhs2.observerCount, 0)

        // Also bind property to the second observable value
        _ = property <~ rhs2
        XCTAssertEqual(property.get(), "initial rhs2 value")
        XCTAssertEqual(values, ["initial rhs1 value", "rhs1 was updated", "initial rhs2 value"])
        XCTAssertEqual(rhs1.observerCount, 1)
        XCTAssertEqual(rhs2.observerCount, 1)

        // Change the second observable value and verify that property's value is updated
        rhs2.update("rhs2 was updated", ChangeMetadata(transient: false))
        XCTAssertEqual(property.get(), "rhs2 was updated")
        XCTAssertEqual(values, ["initial rhs1 value", "rhs1 was updated", "initial rhs2 value", "rhs2 was updated"])
        XCTAssertEqual(rhs1.observerCount, 1)
        XCTAssertEqual(rhs2.observerCount, 1)

        // Unbind the first property and verify that property's value is unaffected
        binding1.unbind()
        XCTAssertEqual(property.get(), "rhs2 was updated")
        XCTAssertEqual(values, ["initial rhs1 value", "rhs1 was updated", "initial rhs2 value", "rhs2 was updated"])
        XCTAssertEqual(rhs1.observerCount, 0)
        XCTAssertEqual(rhs2.observerCount, 1)

        // Change the first observable value and verify that property's value is unaffected
        rhs1.update("rhs1 was updated after unbind", ChangeMetadata(transient: false))
        XCTAssertEqual(property.get(), "rhs2 was updated")
        XCTAssertEqual(values, ["initial rhs1 value", "rhs1 was updated", "initial rhs2 value", "rhs2 was updated"])
        XCTAssertEqual(rhs1.observerCount, 0)
        XCTAssertEqual(rhs2.observerCount, 1)

        // Change the second observable value and verify that property's value is updated
        rhs2.update("rhs2 was updated again", ChangeMetadata(transient: false))
        XCTAssertEqual(property.get(), "rhs2 was updated again")
        XCTAssertEqual(values, ["initial rhs1 value", "rhs1 was updated", "initial rhs2 value", "rhs2 was updated", "rhs2 was updated again"])
        XCTAssertEqual(rhs1.observerCount, 0)
        XCTAssertEqual(rhs2.observerCount, 1)

        // Nil out the property and verify that second observable is unbound
        property = nil
        XCTAssertEqual(values, ["initial rhs1 value", "rhs1 was updated", "initial rhs2 value", "rhs2 was updated", "rhs2 was updated again"])
        XCTAssertEqual(rhs1.observerCount, 0)
        XCTAssertEqual(rhs2.observerCount, 0)
    }
    
    func testBindBidiManyToOne() {
        var lhsValues: [String] = []
        var lhs: ValueBidiProperty<String>! = ValueBidiProperty(
            initialValue: "initial lhs value",
            didSet: { newValue, _ in
                lhsValues.append(newValue)
            }
        )

        // Create two properties so that we can verify the case where a property is bound
        // bidirectionally to multiple properties at the same time
        var rhs1Values: [String] = []
        let rhs1: ValueBidiProperty<String>! = ValueBidiProperty(
            initialValue: "initial rhs1 value",
            didSet: { newValue, _ in
                rhs1Values.append(newValue)
            }
        )

        var rhs2Values: [String] = []
        let rhs2: ValueBidiProperty<String>! = ValueBidiProperty(
            initialValue: "initial rhs2 value",
            didSet: { newValue, _ in
                rhs2Values.append(newValue)
            }
        )
        
        // Verify the initial state
        XCTAssertEqual(lhs.get(), "initial lhs value")
        XCTAssertEqual(rhs1.get(), "initial rhs1 value")
        XCTAssertEqual(rhs2.get(), "initial rhs2 value")
        XCTAssertEqual(lhsValues, [])
        XCTAssertEqual(rhs1Values, [])
        XCTAssertEqual(rhs2Values, [])
        XCTAssertEqual(lhs.signal.observerCount, 0)
        XCTAssertEqual(rhs1.signal.observerCount, 0)
        XCTAssertEqual(rhs2.signal.observerCount, 0)

        // Bidirectionally bind `lhs` to `rhs1`; verify that `lhs` takes on the `rhs1` value
        let binding1 = lhs <~> rhs1
        XCTAssertEqual(lhs.get(), "initial rhs1 value")
        XCTAssertEqual(rhs1.get(), "initial rhs1 value")
        XCTAssertEqual(rhs2.get(), "initial rhs2 value")
        XCTAssertEqual(lhsValues, ["initial rhs1 value"])
        XCTAssertEqual(rhs1Values, [])
        XCTAssertEqual(rhs2Values, [])
        XCTAssertEqual(lhs.signal.observerCount, 1)
        XCTAssertEqual(rhs1.signal.observerCount, 1)
        XCTAssertEqual(rhs2.signal.observerCount, 0)
        
        // Change the rhs1 value and verify that the lhs value is updated
        rhs1.change(newValue: "rhs1 was updated", transient: false)
        XCTAssertEqual(lhs.get(), "rhs1 was updated")
        XCTAssertEqual(rhs1.get(), "rhs1 was updated")
        XCTAssertEqual(rhs2.get(), "initial rhs2 value")
        XCTAssertEqual(lhsValues, ["initial rhs1 value", "rhs1 was updated"])
        XCTAssertEqual(rhs1Values, [])
        XCTAssertEqual(rhs2Values, [])
        XCTAssertEqual(lhs.signal.observerCount, 1)
        XCTAssertEqual(rhs1.signal.observerCount, 1)
        XCTAssertEqual(rhs2.signal.observerCount, 0)

        // Also bidirectionally bind `lhs` to `rhs2`; verify that `lhs` and `rhs1` take on the `rhs2` value
        _ = lhs <~> rhs2
        XCTAssertEqual(lhs.get(), "initial rhs2 value")
        XCTAssertEqual(rhs1.get(), "initial rhs2 value")
        XCTAssertEqual(rhs2.get(), "initial rhs2 value")
        XCTAssertEqual(lhsValues, ["initial rhs1 value", "rhs1 was updated", "initial rhs2 value"])
        XCTAssertEqual(rhs1Values, ["initial rhs2 value"])
        XCTAssertEqual(rhs2Values, [])
        XCTAssertEqual(lhs.signal.observerCount, 2)
        XCTAssertEqual(rhs1.signal.observerCount, 1)
        XCTAssertEqual(rhs2.signal.observerCount, 1)
        
        // Change the rhs2 value and verify that both lhs and rhs2 values are updated
        rhs2.change(newValue: "rhs2 was updated", transient: false)
        XCTAssertEqual(lhs.get(), "rhs2 was updated")
        XCTAssertEqual(rhs1.get(), "rhs2 was updated")
        XCTAssertEqual(rhs2.get(), "rhs2 was updated")
        XCTAssertEqual(lhsValues, ["initial rhs1 value", "rhs1 was updated", "initial rhs2 value", "rhs2 was updated"])
        XCTAssertEqual(rhs1Values, ["initial rhs2 value", "rhs2 was updated"])
        XCTAssertEqual(rhs2Values, [])
        XCTAssertEqual(lhs.signal.observerCount, 2)
        XCTAssertEqual(rhs1.signal.observerCount, 1)
        XCTAssertEqual(rhs2.signal.observerCount, 1)

        // Change the lhs value and verify that both rhs1 and rhs2 values are updated
        lhs.change(newValue: "lhs was updated", transient: false)
        XCTAssertEqual(lhs.get(), "lhs was updated")
        XCTAssertEqual(rhs1.get(), "lhs was updated")
        XCTAssertEqual(rhs2.get(), "lhs was updated")
        XCTAssertEqual(lhsValues, ["initial rhs1 value", "rhs1 was updated", "initial rhs2 value", "rhs2 was updated"])
        XCTAssertEqual(rhs1Values, ["initial rhs2 value", "rhs2 was updated", "lhs was updated"])
        XCTAssertEqual(rhs2Values, ["lhs was updated"])
        XCTAssertEqual(lhs.signal.observerCount, 2)
        XCTAssertEqual(rhs1.signal.observerCount, 1)
        XCTAssertEqual(rhs2.signal.observerCount, 1)

        // Unbind `rhs1` and verify that other properties are unaffected
        binding1.unbind()
        XCTAssertEqual(lhs.get(), "lhs was updated")
        XCTAssertEqual(rhs1.get(), "lhs was updated")
        XCTAssertEqual(rhs2.get(), "lhs was updated")
        XCTAssertEqual(lhsValues, ["initial rhs1 value", "rhs1 was updated", "initial rhs2 value", "rhs2 was updated"])
        XCTAssertEqual(rhs1Values, ["initial rhs2 value", "rhs2 was updated", "lhs was updated"])
        XCTAssertEqual(rhs2Values, ["lhs was updated"])
        XCTAssertEqual(lhs.signal.observerCount, 1)
        XCTAssertEqual(rhs1.signal.observerCount, 0)
        XCTAssertEqual(rhs2.signal.observerCount, 1)

        // Change the rhs1 value and verify that the other properties are unaffected
        rhs1.change(newValue: "rhs1 was updated after unbind", transient: false)
        XCTAssertEqual(lhs.get(), "lhs was updated")
        XCTAssertEqual(rhs1.get(), "rhs1 was updated after unbind")
        XCTAssertEqual(rhs2.get(), "lhs was updated")
        XCTAssertEqual(lhsValues, ["initial rhs1 value", "rhs1 was updated", "initial rhs2 value", "rhs2 was updated"])
        XCTAssertEqual(rhs1Values, ["initial rhs2 value", "rhs2 was updated", "lhs was updated"])
        XCTAssertEqual(rhs2Values, ["lhs was updated"])
        XCTAssertEqual(lhs.signal.observerCount, 1)
        XCTAssertEqual(rhs1.signal.observerCount, 0)
        XCTAssertEqual(rhs2.signal.observerCount, 1)

        // Change the rhs2 value again and verify that only the lhs value is updated
        rhs2.change(newValue: "rhs2 was updated again", transient: false)
        XCTAssertEqual(lhs.get(), "rhs2 was updated again")
        XCTAssertEqual(rhs1.get(), "rhs1 was updated after unbind")
        XCTAssertEqual(rhs2.get(), "rhs2 was updated again")
        XCTAssertEqual(lhsValues, ["initial rhs1 value", "rhs1 was updated", "initial rhs2 value", "rhs2 was updated", "rhs2 was updated again"])
        XCTAssertEqual(rhs1Values, ["initial rhs2 value", "rhs2 was updated", "lhs was updated"])
        XCTAssertEqual(rhs2Values, ["lhs was updated"])
        XCTAssertEqual(lhs.signal.observerCount, 1)
        XCTAssertEqual(rhs1.signal.observerCount, 0)
        XCTAssertEqual(rhs2.signal.observerCount, 1)

        // Nil out `lhs` and verify that `rhs2` is unbound
        lhs = nil
        XCTAssertEqual(rhs1.get(), "rhs1 was updated after unbind")
        XCTAssertEqual(rhs2.get(), "rhs2 was updated again")
        XCTAssertEqual(lhsValues, ["initial rhs1 value", "rhs1 was updated", "initial rhs2 value", "rhs2 was updated", "rhs2 was updated again"])
        XCTAssertEqual(rhs1Values, ["initial rhs2 value", "rhs2 was updated", "lhs was updated"])
        XCTAssertEqual(rhs2Values, ["lhs was updated"])
        XCTAssertEqual(rhs1.signal.observerCount, 0)
        XCTAssertEqual(rhs2.signal.observerCount, 0)
    }
}
