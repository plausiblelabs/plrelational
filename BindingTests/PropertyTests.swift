//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
@testable import Binding

class PropertyTests: XCTestCase {
    
    func testBind() {
        var value: String = ""
        var values: [String] = []
        
        var property: ReadableProperty<String>! = ReadableProperty(
            get: { value },
            set: { newValue, _ in
                value = newValue
                values.append(newValue)
            }
        )
        
        let observable = mutableObservableValue("Hello")
        
        XCTAssertEqual(property.get(), "")
        XCTAssertEqual(values, [])
        XCTAssertEqual(observable.observerCount, 0)

        property <~ observable
        
        XCTAssertEqual(property.get(), "Hello")
        XCTAssertEqual(values, ["Hello"])
        XCTAssertEqual(observable.observerCount, 1)

        observable.update("Hullo", ChangeMetadata(transient: false))
        
        XCTAssertEqual(property.get(), "Hullo")
        XCTAssertEqual(values, ["Hello", "Hullo"])
        XCTAssertEqual(observable.observerCount, 1)
        
        property.unbind()

        XCTAssertEqual(property.get(), "Hullo")
        XCTAssertEqual(values, ["Hello", "Hullo"])
        XCTAssertEqual(observable.observerCount, 0)

        property <~ observable
        
        XCTAssertEqual(values, ["Hello", "Hullo", "Hullo"])
        XCTAssertEqual(observable.observerCount, 1)

        property = nil
        
        XCTAssertEqual(values, ["Hello", "Hullo", "Hullo"])
        XCTAssertEqual(observable.observerCount, 0)
    }
    
    func testBindBidi() {
        var lhsValue = "initial lhsValue"
        var lhsValues: [String] = []

        let lhs: MutableBidiProperty<String>! = MutableBidiProperty(
            get: { lhsValue },
            set: { newValue, _ in
                lhsValue = newValue
                lhsValues.append(newValue)
            }
        )
        
        var rhsValue = "initial rhsValue"
        var rhsValues: [String] = []
        
        let rhs: MutableBidiProperty<String>! = MutableBidiProperty(
            get: { rhsValue },
            set: { newValue, _ in
                rhsValue = newValue
                rhsValues.append(newValue)
            }
        )

        XCTAssertEqual(lhs.get(), "initial lhsValue")
        XCTAssertEqual(rhs.get(), "initial rhsValue")
        XCTAssertEqual(lhsValues, [])
        XCTAssertEqual(rhsValues, [])
        XCTAssertEqual(lhs.signal.observerCount, 0)
        XCTAssertEqual(rhs.signal.observerCount, 0)
        
        lhs <~> rhs
        
        XCTAssertEqual(lhs.get(), "initial rhsValue")
        XCTAssertEqual(rhs.get(), "initial rhsValue")
        XCTAssertEqual(lhsValues, ["initial rhsValue"])
        XCTAssertEqual(rhsValues, [])
        XCTAssertEqual(lhs.signal.observerCount, 1)
        XCTAssertEqual(rhs.signal.observerCount, 1)

        rhsValue = "hello from rhs"
        rhs.changed(transient: false)
        
        XCTAssertEqual(lhs.get(), "hello from rhs")
        XCTAssertEqual(rhs.get(), "hello from rhs")
        XCTAssertEqual(lhsValues, ["initial rhsValue", "hello from rhs"])
        XCTAssertEqual(rhsValues, [])
        XCTAssertEqual(lhs.signal.observerCount, 1)
        XCTAssertEqual(rhs.signal.observerCount, 1)

        lhsValue = "hello from lhs"
        lhs.changed(transient: false)
        
        XCTAssertEqual(lhs.get(), "hello from lhs")
        XCTAssertEqual(rhs.get(), "hello from lhs")
        XCTAssertEqual(lhsValues, ["initial rhsValue", "hello from rhs"])
        XCTAssertEqual(rhsValues, ["hello from lhs"])
        XCTAssertEqual(lhs.signal.observerCount, 1)
        XCTAssertEqual(rhs.signal.observerCount, 1)

        lhs.unbind()

        XCTAssertEqual(lhs.get(), "hello from lhs")
        XCTAssertEqual(rhs.get(), "hello from lhs")
        XCTAssertEqual(lhsValues, ["initial rhsValue", "hello from rhs"])
        XCTAssertEqual(rhsValues, ["hello from lhs"])
        XCTAssertEqual(lhs.signal.observerCount, 0)
        XCTAssertEqual(rhs.signal.observerCount, 0)
    }
}
