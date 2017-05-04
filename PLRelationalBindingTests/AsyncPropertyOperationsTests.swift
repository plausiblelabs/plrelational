//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
@testable import PLRelationalBinding

class AsyncPropertyOperationsTests: BindingTestCase {
    
    func testMap() {
        let (property, notify) = AsyncReadableProperty<Bool>.pipe()
        let mapped = property.map{ $0 ? 1 : 0 }
        let observer = IntObserver()
        
        func verify(value: Int?, changes: [Int], willChangeCount: Int, didChangeCount: Int, file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(mapped.value, value, file: file, line: line)
            XCTAssertEqual(observer.changes, changes, file: file, line: line)
            XCTAssertEqual(observer.willChangeCount, willChangeCount, file: file, line: line)
            XCTAssertEqual(observer.didChangeCount, didChangeCount, file: file, line: line)
        }
        
        verify(value: nil, changes: [], willChangeCount: 0, didChangeCount: 0)
        
        // TODO: Use PipeSignal.onObserve to simulate initial async load when first observer attached
        let removal = observer.observe(mapped.signal)
        verify(value: nil, changes: [], willChangeCount: 0, didChangeCount: 0)

        notify.valueWillChange()
        notify.valueChanging(true, transient: false)
        notify.valueDidChange()
        verify(value: 1, changes: [1], willChangeCount: 1, didChangeCount: 1)

        // TODO: Use isRepeat to avoid duplicates?
        
        notify.valueWillChange()
        notify.valueChanging(false, transient: false)
        notify.valueDidChange()
        verify(value: 0, changes: [1, 0], willChangeCount: 2, didChangeCount: 2)

        removal()
    }
    
//    func testFlatMap() {
//        let (boolProperty, boolNotify) = AsyncReadableProperty<Bool>.pipe(initialValue: nil)
//        
//        var stringNotify: Signal<String>.Notify? = nil
//        let mapped = boolProperty.flatMap{ value -> AsyncReadableProperty<String> in
//            let (property, notify) = AsyncReadableProperty<String>.pipe(initialValue: "Loading for \(value)")
//            stringNotify = notify
//            return property
//        }
//        
//        var changeObserved = false
//        _ = mapped.signal.observe({ _ in changeObserved = true })
////        mapped.start()
//        
//        XCTAssertEqual(mapped.value, nil)
//        XCTAssertNil(stringNotify)
//        XCTAssertEqual(changeObserved, false)
//        changeObserved = false
//        
//        boolNotify.valueChanging(true, transient: false)
//        XCTAssertEqual(boolProperty.value, true)
//        XCTAssertEqual(mapped.value, "Loading for true")
//        XCTAssertNotNil(stringNotify)
//        XCTAssertEqual(changeObserved, true)
//        changeObserved = false
//
//        stringNotify!.valueChanging("Loaded true!", transient: false)
//        XCTAssertEqual(boolProperty.value, true)
//        XCTAssertEqual(mapped.value, "Loaded true!")
//        XCTAssertEqual(changeObserved, true)
//        changeObserved = false
//
//        stringNotify!.valueChanging("Loaded true again!", transient: false)
//        XCTAssertEqual(boolProperty.value, true)
//        XCTAssertEqual(mapped.value, "Loaded true again!")
//        XCTAssertEqual(changeObserved, true)
//        changeObserved = false
//
//        boolNotify.valueChanging(false, transient: false)
//        XCTAssertEqual(boolProperty.value, false)
//        XCTAssertEqual(mapped.value, "Loading for false")
//        XCTAssertNotNil(stringNotify)
//        XCTAssertEqual(changeObserved, true)
//        changeObserved = false
//        
//        stringNotify!.valueChanging("Loaded false!", transient: false)
//        XCTAssertEqual(boolProperty.value, false)
//        XCTAssertEqual(mapped.value, "Loaded false!")
//        XCTAssertEqual(changeObserved, true)
//        changeObserved = false
//        
//        stringNotify!.valueChanging("Loaded false again!", transient: false)
//        XCTAssertEqual(boolProperty.value, false)
//        XCTAssertEqual(mapped.value, "Loaded false again!")
//        XCTAssertEqual(changeObserved, true)
//        changeObserved = false
//    }
    
    func testZip() {
        let (property1, notify1) = AsyncReadableProperty<Bool>.pipe(initialValue: nil)
        let (property2, notify2) = AsyncReadableProperty<Bool>.pipe(initialValue: nil)
        let zipped = zip(property1, property2)
        var changeObserved = false
        _ = zipped.signal.observe({ _ in changeObserved = true })
//        zipped.start()
        
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
    
    func testZipWithNonNilInitialValues() {
        let (property1, notify1) = AsyncReadableProperty<Bool>.pipe(initialValue: false)
        let (property2, notify2) = AsyncReadableProperty<String>.pipe(initialValue: "foo")
        let zipped = zip(property1, property2)
        var changeObserved = false
        _ = zipped.signal.observe({ _ in changeObserved = true })
//        zipped.start()
        
        XCTAssertEqual(zipped.value?.0, false)
        XCTAssertEqual(zipped.value?.1, "foo")
        XCTAssertEqual(changeObserved, false)
        changeObserved = false
        
        notify1.valueChanging(true, transient: false)
        XCTAssertEqual(zipped.value?.0, true)
        XCTAssertEqual(zipped.value?.1, "foo")
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
        
        notify2.valueChanging("bar", transient: false)
        XCTAssertEqual(zipped.value?.0, true)
        XCTAssertEqual(zipped.value?.1, "bar")
        XCTAssertEqual(changeObserved, true)
        changeObserved = false
    }
    
    func testNot() {
        let (property, notify) = AsyncReadableProperty<Bool>.pipe(initialValue: false)
        let mapped = !property
        var changeObserved = false
        _ = mapped.signal.observe({ _ in changeObserved = true })
//        mapped.start()
        
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
