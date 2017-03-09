//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
@testable import PLRelationalBinding

class AsyncPropertyOperationsTests: BindingTestCase {
    
    func testMap() {
        let (property, notify) = AsyncReadableProperty<Bool>.pipe(initialValue: false)
        let mapped = property.map{ $0 ? 1 : 0 }
        var changeObserved = false
        _ = mapped.signal.observe({ _ in changeObserved = true })
        mapped.start()
        
        XCTAssertEqual(mapped.value, 0)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        notify.valueChanging(true, transient: false)
        XCTAssertEqual(mapped.value, 1)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        // TODO: Need to pass isRepeat func to pipe() so that we can avoid duplicates
//        notify.valueChanging(true, transient: false)
//        XCTAssertEqual(mapped.value, 1)
//        XCTAssertEqual(changeObserved, false)
//        changeObserved = false
        
        notify.valueChanging(false, transient: false)
        XCTAssertEqual(mapped.value, 0)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
    }
    
    func testFlatMap() {
        let (boolProperty, boolNotify) = AsyncReadableProperty<Bool>.pipe(initialValue: nil)
        
        var stringNotify: SignalObserver<String>? = nil
        let mapped = boolProperty.flatMap{ value -> AsyncReadableProperty<String> in
            let (property, notify) = AsyncReadableProperty<String>.pipe(initialValue: "Loading for \(value)")
            stringNotify = notify
            return property
        }
        
        var changeObserved = false
        _ = mapped.signal.observe({ _ in changeObserved = true })
        mapped.start()
        
        XCTAssertEqual(mapped.value, nil)
        XCTAssertNil(stringNotify)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        boolNotify.valueChanging(true, transient: false)
        XCTAssertEqual(boolProperty.value, true)
        XCTAssertEqual(mapped.value, "Loading for true")
        XCTAssertNotNil(stringNotify)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false

        stringNotify!.valueChanging("Loaded true!", transient: false)
        XCTAssertEqual(boolProperty.value, true)
        XCTAssertEqual(mapped.value, "Loaded true!")
        XCTAssertEqual(changeObserved, true)
        changeObserved = false

        stringNotify!.valueChanging("Loaded true again!", transient: false)
        XCTAssertEqual(boolProperty.value, true)
        XCTAssertEqual(mapped.value, "Loaded true again!")
        XCTAssertEqual(changeObserved, true)
        changeObserved = false

        boolNotify.valueChanging(false, transient: false)
        XCTAssertEqual(boolProperty.value, false)
        XCTAssertEqual(mapped.value, "Loading for false")
        XCTAssertNotNil(stringNotify)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        stringNotify!.valueChanging("Loaded false!", transient: false)
        XCTAssertEqual(boolProperty.value, false)
        XCTAssertEqual(mapped.value, "Loaded false!")
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        stringNotify!.valueChanging("Loaded false again!", transient: false)
        XCTAssertEqual(boolProperty.value, false)
        XCTAssertEqual(mapped.value, "Loaded false again!")
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
    }
    
    func testZip() {
        let (property1, notify1) = AsyncReadableProperty<Bool>.pipe(initialValue: nil)
        let (property2, notify2) = AsyncReadableProperty<Bool>.pipe(initialValue: nil)
        let zipped = zip(property1, property2)
        var changeObserved = false
        _ = zipped.signal.observe({ _ in changeObserved = true })
        zipped.start()
        
        XCTAssertEqual(zipped.value?.0, nil)
        XCTAssertEqual(zipped.value?.1, nil)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        notify1.valueChanging(false, transient: false)
        XCTAssertEqual(zipped.value?.0, nil)
        XCTAssertEqual(zipped.value?.1, nil)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false

        notify2.valueChanging(true, transient: false)
        XCTAssertEqual(zipped.value?.0, false)
        XCTAssertEqual(zipped.value?.1, true)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false

        notify1.valueChanging(true, transient: false)
        XCTAssertEqual(zipped.value?.0, true)
        XCTAssertEqual(zipped.value?.1, true)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
    }
    
    func testNot() {
        let (property, notify) = AsyncReadableProperty<Bool>.pipe(initialValue: false)
        let mapped = !property
        var changeObserved = false
        _ = mapped.signal.observe({ _ in changeObserved = true })
        mapped.start()
        
        XCTAssertEqual(mapped.value, true)
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        notify.valueChanging(true, transient: false)
        XCTAssertEqual(mapped.value, false)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        // TODO: Need to pass isRepeat func to pipe() so that we can avoid duplicates
        
        notify.valueChanging(false, transient: false)
        XCTAssertEqual(mapped.value, true)
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
    }
}
