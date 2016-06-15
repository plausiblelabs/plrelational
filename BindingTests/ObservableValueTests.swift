//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
@testable import Binding

class ObservableValueTests: BindingTestCase {
    
    func testMap() {
        let observable = mutableObservableValue(false)
        let mapped = observable.map{ $0 ? 1 : 0 }
        var changeObserved = false
        _ = mapped.addChangeObserver({ _ in changeObserved = true })
        let metadata = ChangeMetadata(transient: false)
        
        XCTAssertEqual(mapped.value, 0)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false

        observable.update(true, metadata)
        XCTAssertEqual(mapped.value, 1)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        observable.update(true, metadata)
        XCTAssertEqual(mapped.value, 1)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        observable.update(false, metadata)
        XCTAssertEqual(mapped.value, 0)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
    }
    
    func testZip() {
        let observable1 = mutableObservableValue(false)
        let observable2 = mutableObservableValue(false)
        let zipped = zip(observable1, observable2)
        var changeObserved = false
        _ = zipped.addChangeObserver({ _ in changeObserved = true })
        let metadata = ChangeMetadata(transient: false)

        XCTAssertEqual(zipped.value.0, false)
        XCTAssertEqual(zipped.value.1, false)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        observable1.update(true, metadata)
        XCTAssertEqual(zipped.value.0, true)
        XCTAssertEqual(zipped.value.1, false)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        observable2.update(true, metadata)
        XCTAssertEqual(zipped.value.0, true)
        XCTAssertEqual(zipped.value.1, true)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        observable2.update(true, metadata)
        XCTAssertEqual(zipped.value.0, true)
        XCTAssertEqual(zipped.value.1, true)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
    }
    
    func testNot() {
        let observable = mutableObservableValue(false)
        let mapped = not(observable)
        var changeObserved = false
        _ = mapped.addChangeObserver({ _ in changeObserved = true })
        let metadata = ChangeMetadata(transient: false)
        
        XCTAssertEqual(mapped.value, true)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        observable.update(true, metadata)
        XCTAssertEqual(mapped.value, false)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        observable.update(true, metadata)
        XCTAssertEqual(mapped.value, false)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        observable.update(false, metadata)
        XCTAssertEqual(mapped.value, true)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
    }
    
    func testAnyTrue() {
        let observable1 = mutableObservableValue(false)
        let observable2 = mutableObservableValue(false)
        let observables: [ObservableValue<Bool>] = [observable1, observable2]
        let mapped = observables.anyTrue()
        var changeObserved = false
        _ = mapped.addChangeObserver({ _ in changeObserved = true })
        let metadata = ChangeMetadata(transient: false)
        
        XCTAssertEqual(mapped.value, false)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        observable1.update(true, metadata)
        XCTAssertEqual(mapped.value, true)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        observable2.update(true, metadata)
        XCTAssertEqual(mapped.value, true)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        observable2.update(false, metadata)
        XCTAssertEqual(mapped.value, true)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        observable1.update(false, metadata)
        XCTAssertEqual(mapped.value, false)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
    }
    
    func testAllTrue() {
        let observable1 = mutableObservableValue(false)
        let observable2 = mutableObservableValue(false)
        let observables: [ObservableValue<Bool>] = [observable1, observable2]
        let mapped = observables.allTrue()
        var changeObserved = false
        _ = mapped.addChangeObserver({ _ in changeObserved = true })
        let metadata = ChangeMetadata(transient: false)
        
        XCTAssertEqual(mapped.value, false)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        observable1.update(true, metadata)
        XCTAssertEqual(mapped.value, false)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        observable2.update(true, metadata)
        XCTAssertEqual(mapped.value, true)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        observable2.update(false, metadata)
        XCTAssertEqual(mapped.value, false)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        observable1.update(false, metadata)
        XCTAssertEqual(mapped.value, false)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
    }

    func testNoneTrue() {
        let observable1 = mutableObservableValue(false)
        let observable2 = mutableObservableValue(false)
        let observables: [ObservableValue<Bool>] = [observable1, observable2]
        let mapped = observables.noneTrue()
        var changeObserved = false
        _ = mapped.addChangeObserver({ _ in changeObserved = true })
        let metadata = ChangeMetadata(transient: false)
        
        XCTAssertEqual(mapped.value, true)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        observable1.update(true, metadata)
        XCTAssertEqual(mapped.value, false)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        observable2.update(true, metadata)
        XCTAssertEqual(mapped.value, false)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        observable2.update(false, metadata)
        XCTAssertEqual(mapped.value, false)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        observable1.update(false, metadata)
        XCTAssertEqual(mapped.value, true)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
    }

    func testMutableObservableBool() {
        let observable = mutableObservableValue(false)
        var changeObserved = false
        _ = observable.addChangeObserver({ _ in changeObserved = true })
        let metadata = ChangeMetadata(transient: false)

        XCTAssertEqual(observable.value, false)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false

        observable.toggle(metadata)
        XCTAssertEqual(observable.value, true)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false

        observable.toggle(metadata)
        XCTAssertEqual(observable.value, false)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false

        observable.update(true, metadata)
        XCTAssertEqual(observable.value, true)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false

        observable.update(true, metadata)
        XCTAssertEqual(observable.value, true)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
    }
}
