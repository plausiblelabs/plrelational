//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
@testable import Binding

class PropertyTests: XCTestCase {
    
    func testMutableValueProperty() {
        let property = mutableValueProperty(false)
        
        var changeObserved = false
        _ = property.signal.observe({ _ in changeObserved = true })
        
        XCTAssertEqual(property.value, false)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        property.change(true, transient: false)
        XCTAssertEqual(property.value, true)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        property.change(true, transient: false)
        XCTAssertEqual(property.value, true)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
    }
    
    func testExternalValueProperty() {
        var value = false
        let property = ExternalValueProperty(
            get: { return value },
            set: { newValue, _ in value = newValue },
            changeHandler: ChangeHandler()
        )
        
        var changeObserved = false
        _ = property.signal.observe({ _ in changeObserved = true })
        
        XCTAssertEqual(value, false)
        XCTAssertEqual(property.value, false)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        value = true
        property.changed(transient: false)
        XCTAssertEqual(value, true)
        XCTAssertEqual(property.value, true)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false

        // TODO: Unlike MutableValueProperty, ExternalValueProperty doesn't prevent
        // notification when the value is not changing; should it?
//        property.changed(transient: false)
//        XCTAssertEqual(value, true)
//        XCTAssertEqual(property.value, true)
//        XCTAssertEqual(changeObserved, false)
//        changeObserved = false
    }

    func testBind() {
        var lhsValues: [String] = []
        
        var lhs: ReadWriteProperty<String>! = mutableValueProperty("initial lhs value", { newValue, _ in
            lhsValues.append(newValue)
        })
        
        // Create two mutable value properties so that we can verify the case where a property is bound to
        // multiple signals at the same time
        let rhs1 = mutableValueProperty("initial rhs1 value")
        let rhs2 = mutableValueProperty("initial rhs2 value")

        // Verify the initial state
        XCTAssertEqual(lhs.value, "initial lhs value")
        XCTAssertEqual(lhsValues, [])
        XCTAssertEqual(lhs.signal.observerCount, 0)
        XCTAssertEqual(rhs1.signal.observerCount, 0)
        XCTAssertEqual(rhs2.signal.observerCount, 0)

        // Bind lhs property to the first rhs property
        let binding1 = lhs <~ rhs1
        XCTAssertEqual(lhs.value, "initial rhs1 value")
        XCTAssertEqual(lhsValues, ["initial rhs1 value"])
        XCTAssertEqual(lhs.signal.observerCount, 0)
        XCTAssertEqual(rhs1.signal.observerCount, 1)
        XCTAssertEqual(rhs2.signal.observerCount, 0)

        // Change the first rhs property and verify that lhs property's value is updated
        rhs1.change("rhs1 was updated", transient: false)
        XCTAssertEqual(lhs.value, "rhs1 was updated")
        XCTAssertEqual(lhsValues, ["initial rhs1 value", "rhs1 was updated"])
        XCTAssertEqual(lhs.signal.observerCount, 0)
        XCTAssertEqual(rhs1.signal.observerCount, 1)
        XCTAssertEqual(rhs2.signal.observerCount, 0)

        // Also bind lhs property to the second rhs property
        _ = lhs <~ rhs2
        XCTAssertEqual(lhs.value, "initial rhs2 value")
        XCTAssertEqual(lhsValues, ["initial rhs1 value", "rhs1 was updated", "initial rhs2 value"])
        XCTAssertEqual(lhs.signal.observerCount, 0)
        XCTAssertEqual(rhs1.signal.observerCount, 1)
        XCTAssertEqual(rhs2.signal.observerCount, 1)

        // Change the second rhs property's value and verify that lhs property's value is updated
        rhs2.change("rhs2 was updated", transient: false)
        XCTAssertEqual(lhs.value, "rhs2 was updated")
        XCTAssertEqual(lhsValues, ["initial rhs1 value", "rhs1 was updated", "initial rhs2 value", "rhs2 was updated"])
        XCTAssertEqual(lhs.signal.observerCount, 0)
        XCTAssertEqual(rhs1.signal.observerCount, 1)
        XCTAssertEqual(rhs2.signal.observerCount, 1)

        // Unbind the first rhs property and verify that lhs property's value is unaffected
        binding1.unbind()
        XCTAssertEqual(lhs.value, "rhs2 was updated")
        XCTAssertEqual(lhsValues, ["initial rhs1 value", "rhs1 was updated", "initial rhs2 value", "rhs2 was updated"])
        XCTAssertEqual(lhs.signal.observerCount, 0)
        XCTAssertEqual(rhs1.signal.observerCount, 0)
        XCTAssertEqual(rhs2.signal.observerCount, 1)

        // Change the first rhs property's value and verify that lhs property's value is unaffected
        rhs1.change("rhs1 was updated after unbind", transient: false)
        XCTAssertEqual(lhs.value, "rhs2 was updated")
        XCTAssertEqual(lhsValues, ["initial rhs1 value", "rhs1 was updated", "initial rhs2 value", "rhs2 was updated"])
        XCTAssertEqual(lhs.signal.observerCount, 0)
        XCTAssertEqual(rhs1.signal.observerCount, 0)
        XCTAssertEqual(rhs2.signal.observerCount, 1)

        // Change the second rhs property's value and verify that lhs property's value is updated
        rhs2.change("rhs2 was updated again", transient: false)
        XCTAssertEqual(lhs.value, "rhs2 was updated again")
        XCTAssertEqual(lhsValues, ["initial rhs1 value", "rhs1 was updated", "initial rhs2 value", "rhs2 was updated", "rhs2 was updated again"])
        XCTAssertEqual(lhs.signal.observerCount, 0)
        XCTAssertEqual(rhs1.signal.observerCount, 0)
        XCTAssertEqual(rhs2.signal.observerCount, 1)

        // Nil out the lhs property and verify that second rhs property is unbound
        lhs = nil
        XCTAssertEqual(lhsValues, ["initial rhs1 value", "rhs1 was updated", "initial rhs2 value", "rhs2 was updated", "rhs2 was updated again"])
        XCTAssertEqual(rhs1.signal.observerCount, 0)
        XCTAssertEqual(rhs2.signal.observerCount, 0)
    }
    
    func testChangeHandlerWithBindAndUnbind() {
        var lhsLockCount = 0
        var lhsUnlockCount = 0
        let lhsChangeHandler = ChangeHandler(
            onLock: { lhsLockCount += 1 },
            onUnlock: { lhsUnlockCount += 1 }
        )
        
        let lhs = mutableValueProperty("hi", lhsChangeHandler)
        XCTAssertEqual(lhsLockCount, 0)
        XCTAssertEqual(lhsUnlockCount, 0)
        
        let rhs = mutableValueProperty("yo")
        // XXX: This is a shady way of simulating the case where the `rhs` property's signal is in a changing
        // state when we bind it to `lhs`
        rhs.signal.notifyWillChange()
        XCTAssertEqual(lhsLockCount, 0)
        XCTAssertEqual(lhsUnlockCount, 0)
        
        let binding = lhs <~ rhs
        XCTAssertEqual(lhsLockCount, 1)
        XCTAssertEqual(lhsUnlockCount, 0)

        // Verify that ChangeHandler is unlocked after we unbind `rhs`
        binding.unbind()
        XCTAssertEqual(lhsLockCount, 1)
        XCTAssertEqual(lhsUnlockCount, 1)
    }

    func testChangeHandlerWithBindAndUnbindAll() {
        var lhsLockCount = 0
        var lhsUnlockCount = 0
        let lhsChangeHandler = ChangeHandler(
            onLock: { lhsLockCount += 1 },
            onUnlock: { lhsUnlockCount += 1 }
        )
        
        let lhs = mutableValueProperty("hi", lhsChangeHandler)
        XCTAssertEqual(lhsLockCount, 0)
        XCTAssertEqual(lhsUnlockCount, 0)
        
        let rhs = mutableValueProperty("yo")
        // XXX: This is a shady way of simulating the case where the `rhs` property's signal is in a changing
        // state when we bind it to `lhs`
        rhs.signal.notifyWillChange()
        XCTAssertEqual(lhsLockCount, 0)
        XCTAssertEqual(lhsUnlockCount, 0)
        
        lhs <~ rhs
        XCTAssertEqual(lhsLockCount, 1)
        XCTAssertEqual(lhsUnlockCount, 0)
        
        // Verify that ChangeHandler is unlocked after we unbind all
        lhs.unbindAll()
        XCTAssertEqual(lhsLockCount, 1)
        XCTAssertEqual(lhsUnlockCount, 1)
    }

    func testBindBidiManyToOne() {
        var lhsValues: [String] = []
        var lhs: MutableValueProperty<String>! = mutableValueProperty("initial lhs value", { newValue, _ in
            lhsValues.append(newValue)
        })

        // Create two properties so that we can verify the case where a property is bound
        // bidirectionally to multiple properties at the same time
        var rhs1Values: [String] = []
        let rhs1: MutableValueProperty<String>! = mutableValueProperty("initial rhs1 value", { newValue, _ in
            rhs1Values.append(newValue)
        })

        var rhs2Values: [String] = []
        let rhs2: MutableValueProperty<String>! = mutableValueProperty("initial rhs2 value", { newValue, _ in
            rhs2Values.append(newValue)
        })
        
        // Verify the initial state
        XCTAssertEqual(lhs.value, "initial lhs value")
        XCTAssertEqual(rhs1.value, "initial rhs1 value")
        XCTAssertEqual(rhs2.value, "initial rhs2 value")
        XCTAssertEqual(lhsValues, [])
        XCTAssertEqual(rhs1Values, [])
        XCTAssertEqual(rhs2Values, [])
        XCTAssertEqual(lhs.signal.observerCount, 0)
        XCTAssertEqual(rhs1.signal.observerCount, 0)
        XCTAssertEqual(rhs2.signal.observerCount, 0)

        // Bidirectionally bind `lhs` to `rhs1`; verify that `lhs` takes on the `rhs1` value
        let binding1 = lhs <~> rhs1
        XCTAssertEqual(lhs.value, "initial rhs1 value")
        XCTAssertEqual(rhs1.value, "initial rhs1 value")
        XCTAssertEqual(rhs2.value, "initial rhs2 value")
        XCTAssertEqual(lhsValues, ["initial rhs1 value"])
        XCTAssertEqual(rhs1Values, [])
        XCTAssertEqual(rhs2Values, [])
        XCTAssertEqual(lhs.signal.observerCount, 1)
        XCTAssertEqual(rhs1.signal.observerCount, 1)
        XCTAssertEqual(rhs2.signal.observerCount, 0)
        
        // Change the rhs1 value and verify that the lhs value is updated
        rhs1.change("rhs1 was updated", transient: false)
        XCTAssertEqual(lhs.value, "rhs1 was updated")
        XCTAssertEqual(rhs1.value, "rhs1 was updated")
        XCTAssertEqual(rhs2.value, "initial rhs2 value")
        XCTAssertEqual(lhsValues, ["initial rhs1 value", "rhs1 was updated"])
        XCTAssertEqual(rhs1Values, [])
        XCTAssertEqual(rhs2Values, [])
        XCTAssertEqual(lhs.signal.observerCount, 1)
        XCTAssertEqual(rhs1.signal.observerCount, 1)
        XCTAssertEqual(rhs2.signal.observerCount, 0)

        // Also bidirectionally bind `lhs` to `rhs2`; verify that `lhs` and `rhs1` take on the `rhs2` value
        _ = lhs <~> rhs2
        XCTAssertEqual(lhs.value, "initial rhs2 value")
        XCTAssertEqual(rhs1.value, "initial rhs2 value")
        XCTAssertEqual(rhs2.value, "initial rhs2 value")
        XCTAssertEqual(lhsValues, ["initial rhs1 value", "rhs1 was updated", "initial rhs2 value"])
        XCTAssertEqual(rhs1Values, ["initial rhs2 value"])
        XCTAssertEqual(rhs2Values, [])
        XCTAssertEqual(lhs.signal.observerCount, 2)
        XCTAssertEqual(rhs1.signal.observerCount, 1)
        XCTAssertEqual(rhs2.signal.observerCount, 1)
        
        // Change the rhs2 value and verify that both lhs and rhs2 values are updated
        rhs2.change("rhs2 was updated", transient: false)
        XCTAssertEqual(lhs.value, "rhs2 was updated")
        XCTAssertEqual(rhs1.value, "rhs2 was updated")
        XCTAssertEqual(rhs2.value, "rhs2 was updated")
        XCTAssertEqual(lhsValues, ["initial rhs1 value", "rhs1 was updated", "initial rhs2 value", "rhs2 was updated"])
        XCTAssertEqual(rhs1Values, ["initial rhs2 value", "rhs2 was updated"])
        XCTAssertEqual(rhs2Values, [])
        XCTAssertEqual(lhs.signal.observerCount, 2)
        XCTAssertEqual(rhs1.signal.observerCount, 1)
        XCTAssertEqual(rhs2.signal.observerCount, 1)

        // Change the lhs value and verify that both rhs1 and rhs2 values are updated
        lhs.change("lhs was updated", transient: false)
        XCTAssertEqual(lhs.value, "lhs was updated")
        XCTAssertEqual(rhs1.value, "lhs was updated")
        XCTAssertEqual(rhs2.value, "lhs was updated")
        XCTAssertEqual(lhsValues, ["initial rhs1 value", "rhs1 was updated", "initial rhs2 value", "rhs2 was updated"])
        XCTAssertEqual(rhs1Values, ["initial rhs2 value", "rhs2 was updated", "lhs was updated"])
        XCTAssertEqual(rhs2Values, ["lhs was updated"])
        XCTAssertEqual(lhs.signal.observerCount, 2)
        XCTAssertEqual(rhs1.signal.observerCount, 1)
        XCTAssertEqual(rhs2.signal.observerCount, 1)

        // Unbind `rhs1` and verify that other properties are unaffected
        binding1.unbind()
        XCTAssertEqual(lhs.value, "lhs was updated")
        XCTAssertEqual(rhs1.value, "lhs was updated")
        XCTAssertEqual(rhs2.value, "lhs was updated")
        XCTAssertEqual(lhsValues, ["initial rhs1 value", "rhs1 was updated", "initial rhs2 value", "rhs2 was updated"])
        XCTAssertEqual(rhs1Values, ["initial rhs2 value", "rhs2 was updated", "lhs was updated"])
        XCTAssertEqual(rhs2Values, ["lhs was updated"])
        XCTAssertEqual(lhs.signal.observerCount, 1)
        XCTAssertEqual(rhs1.signal.observerCount, 0)
        XCTAssertEqual(rhs2.signal.observerCount, 1)

        // Change the rhs1 value and verify that the other properties are unaffected
        rhs1.change("rhs1 was updated after unbind", transient: false)
        XCTAssertEqual(lhs.value, "lhs was updated")
        XCTAssertEqual(rhs1.value, "rhs1 was updated after unbind")
        XCTAssertEqual(rhs2.value, "lhs was updated")
        XCTAssertEqual(lhsValues, ["initial rhs1 value", "rhs1 was updated", "initial rhs2 value", "rhs2 was updated"])
        XCTAssertEqual(rhs1Values, ["initial rhs2 value", "rhs2 was updated", "lhs was updated"])
        XCTAssertEqual(rhs2Values, ["lhs was updated"])
        XCTAssertEqual(lhs.signal.observerCount, 1)
        XCTAssertEqual(rhs1.signal.observerCount, 0)
        XCTAssertEqual(rhs2.signal.observerCount, 1)

        // Change the rhs2 value again and verify that only the lhs value is updated
        rhs2.change("rhs2 was updated again", transient: false)
        XCTAssertEqual(lhs.value, "rhs2 was updated again")
        XCTAssertEqual(rhs1.value, "rhs1 was updated after unbind")
        XCTAssertEqual(rhs2.value, "rhs2 was updated again")
        XCTAssertEqual(lhsValues, ["initial rhs1 value", "rhs1 was updated", "initial rhs2 value", "rhs2 was updated", "rhs2 was updated again"])
        XCTAssertEqual(rhs1Values, ["initial rhs2 value", "rhs2 was updated", "lhs was updated"])
        XCTAssertEqual(rhs2Values, ["lhs was updated"])
        XCTAssertEqual(lhs.signal.observerCount, 1)
        XCTAssertEqual(rhs1.signal.observerCount, 0)
        XCTAssertEqual(rhs2.signal.observerCount, 1)

        // Nil out `lhs` and verify that `rhs2` is unbound
        lhs = nil
        XCTAssertEqual(rhs1.value, "rhs1 was updated after unbind")
        XCTAssertEqual(rhs2.value, "rhs2 was updated again")
        XCTAssertEqual(lhsValues, ["initial rhs1 value", "rhs1 was updated", "initial rhs2 value", "rhs2 was updated", "rhs2 was updated again"])
        XCTAssertEqual(rhs1Values, ["initial rhs2 value", "rhs2 was updated", "lhs was updated"])
        XCTAssertEqual(rhs2Values, ["lhs was updated"])
        XCTAssertEqual(rhs1.signal.observerCount, 0)
        XCTAssertEqual(rhs2.signal.observerCount, 0)
    }

    func testConnectBidi() {
        var boolProperty: MutableValueProperty<Bool>! = mutableValueProperty(false)
        let stringProperty = mutableValueProperty("")
        let intProperty = mutableValueProperty(6)
        
        XCTAssertEqual(boolProperty.value, false)
        XCTAssertEqual(stringProperty.value, "")
        XCTAssertEqual(intProperty.value, 6)
        XCTAssertEqual(boolProperty.signal.observerCount, 0)
        XCTAssertEqual(stringProperty.signal.observerCount, 0)
        XCTAssertEqual(intProperty.signal.observerCount, 0)
        
        // We set up the connections such that `boolProperty` is the "master" value and the others
        // are secondary:
        //   - If `boolProperty` is updated, then `stringProperty` and `intProperty` are updated.
        //   - If `stringProperty` is updated, then `boolProperty` is updated, and `intProperty` should
        //     but updated transitively.
        //   - If `intProperty` is updated, then `boolProperty` is updated, and `stringProperty` should
        //     but updated transitively.
        
        // For this reverse case, we won't update the master value if the string is not "true" or "false"
        // (just to exercise the .NoChange case)
        _ = boolProperty.connectBidi(
            stringProperty,
            forward: {
                // Bool -> String
                .change($0.description)
            },
            reverse: {
                // String -> Bool
                switch $0 {
                case "true":
                    return .change(true)
                case "false":
                    return .change(false)
                default:
                    return .noChange
                }
            }
        )

        // Verify that stringProperty takes on boolProperty's value
        XCTAssertEqual(boolProperty.value, false)
        XCTAssertEqual(stringProperty.value, "false")
        XCTAssertEqual(intProperty.value, 6)
        XCTAssertEqual(boolProperty.signal.observerCount, 1)
        XCTAssertEqual(stringProperty.signal.observerCount, 1)
        XCTAssertEqual(intProperty.signal.observerCount, 0)
        
        // For this reverse case, we'll treat any non-zero value as true
        _ = boolProperty.connectBidi(
            intProperty,
            forward: {
                // Bool -> Int
                .change($0 ? 1 : 0)
            },
            reverse: {
                // Int -> Bool
                .change($0 != 0)
            }
        )
        
        XCTAssertEqual(boolProperty.value, false)
        XCTAssertEqual(stringProperty.value, "false")
        XCTAssertEqual(intProperty.value, 0)
        XCTAssertEqual(boolProperty.signal.observerCount, 2)
        XCTAssertEqual(stringProperty.signal.observerCount, 1)
        XCTAssertEqual(intProperty.signal.observerCount, 1)
        
        // Update boolProperty and verify that secondary ones are updated
        boolProperty.change(true, transient: false)
        XCTAssertEqual(boolProperty.value, true)
        XCTAssertEqual(stringProperty.value, "true")
        XCTAssertEqual(intProperty.value, 1)
        
        // Update stringProperty and verify that others are updated
        stringProperty.change("false", transient: false)
        XCTAssertEqual(boolProperty.value, false)
        XCTAssertEqual(stringProperty.value, "false")
        XCTAssertEqual(intProperty.value, 0)
        
        // Update stringProperty and verify that there is no change reported
        // TODO: Verify the no change part
        stringProperty.change("false", transient: false)
        XCTAssertEqual(boolProperty.value, false)
        XCTAssertEqual(stringProperty.value, "false")
        XCTAssertEqual(intProperty.value, 0)
        
        // Update intProperty and verify that others are updated
        intProperty.change(8, transient: false)
        XCTAssertEqual(boolProperty.value, true)
        XCTAssertEqual(stringProperty.value, "true")
        XCTAssertEqual(intProperty.value, 8)
        
        // Update stringProperty with an unknown value and verify that others are not updated
        stringProperty.change("foo", transient: false)
        XCTAssertEqual(boolProperty.value, true)
        XCTAssertEqual(stringProperty.value, "foo")
        XCTAssertEqual(intProperty.value, 8)
        
        // Update stringProperty with a known value and verify that others are updated
        stringProperty.change("false", transient: false)
        XCTAssertEqual(boolProperty.value, false)
        XCTAssertEqual(stringProperty.value, "false")
        XCTAssertEqual(intProperty.value, 0)
        
        // Nil out boolProperty and verify that the others are unbound
        boolProperty = nil
        XCTAssertEqual(stringProperty.signal.observerCount, 0)
        XCTAssertEqual(intProperty.signal.observerCount, 0)
    }
    
    func testActionProperty() {
        var changeCount = 0
        let property = ActionProperty { () in
            changeCount += 1
        }

        XCTAssertEqual(changeCount, 0)

        let (signal, notify) = Signal<()>.pipe()
        XCTAssertEqual(signal.observerCount, 0)
        
        let binding = signal ~~> property
        XCTAssertEqual(changeCount, 0)
        XCTAssertEqual(signal.observerCount, 1)
        
        notify.valueChanging((), ChangeMetadata(transient: false))
        XCTAssertEqual(changeCount, 1)
        XCTAssertEqual(signal.observerCount, 1)
        
        notify.valueChanging((), ChangeMetadata(transient: false))
        XCTAssertEqual(changeCount, 2)
        XCTAssertEqual(signal.observerCount, 1)
        
        binding.unbind()
        XCTAssertEqual(changeCount, 2)
        XCTAssertEqual(signal.observerCount, 0)
    }
}
