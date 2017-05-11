//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
@testable import PLRelationalBinding

class AsyncPropertyOperationsTests: BindingTestCase {
    
    func testMap() {
        let source = PipeSignal<Bool>()
        let property = AsyncReadableProperty(signal: source)
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

        source.notifyValueChangedAsync(true)
        verify(value: 1, changes: [1], willChangeCount: 1, didChangeCount: 1)

        // TODO: Use isRepeat to avoid duplicates?
        
        source.notifyValueChangedAsync(false)
        verify(value: 0, changes: [1, 0], willChangeCount: 2, didChangeCount: 2)

        removal()
    }
    
    func testMapLifetime() {
        let source = SourceSignal<Bool>()
        let property = AsyncReadableProperty(signal: source)
        
        var mapped: AsyncReadableProperty<Int>? = property.map{ $0 ? 1 : 0 }
        weak var weakMapped: AsyncReadableProperty<Int>? = mapped
        
        XCTAssertNotNil(weakMapped)
        XCTAssertEqual(weakMapped!.value, nil)
        
        source.notifyValueChanging(true)
        XCTAssertEqual(weakMapped!.value, 1)
        
        // Verify that property weakly observes its underlying signal and does not leave dangling strong references
        // that prevent the property from being deinitialized
        mapped = nil
        XCTAssertNil(weakMapped)
    }

    func testFlatMap() {
        let intSource = PipeSignal<Int>()
        let intProperty = intSource.property()

        var stringValue = "Nothing"
        var stringSource: PipeSignal<String>? = nil
        func changeString(_ newValue: String) {
            stringValue = newValue
            stringSource!.notifyValueChanging(newValue)
        }
        
        let mapped = intProperty.flatMap{ value -> AsyncReadableProperty<String> in
            stringValue = "Loading for \(value)"
            stringSource = PipeSignal<String>()
            stringSource!.onObserve = { observer in
                observer.notifyValueChanging(stringValue)
            }
            return stringSource!.property()
        }

        let observer = StringObserver()
        
        func verify(value: String?, changes: [String], willChangeCount: Int, didChangeCount: Int, file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(mapped.value, value, file: file, line: line)
            XCTAssertEqual(observer.changes, changes, file: file, line: line)
            XCTAssertEqual(observer.willChangeCount, willChangeCount, file: file, line: line)
            XCTAssertEqual(observer.didChangeCount, didChangeCount, file: file, line: line)
        }
        
        let removal = observer.observe(mapped.signal)
        verify(value: nil, changes: [], willChangeCount: 0, didChangeCount: 0)
        XCTAssertNil(stringSource)
        
        intSource.notifyValueChangedAsync(1)
        verify(value: "Loading for 1", changes: ["Loading for 1"], willChangeCount: 1, didChangeCount: 1)
        observer.reset()
        
        changeString("Loaded 1!")
        verify(value: "Loaded 1!", changes: ["Loaded 1!"], willChangeCount: 0, didChangeCount: 0)
        observer.reset()

        changeString("Loaded 1 again!")
        verify(value: "Loaded 1 again!", changes: ["Loaded 1 again!"], willChangeCount: 0, didChangeCount: 0)
        observer.reset()
        
        intSource.notifyValueChangedAsync(2)
        verify(value: "Loading for 2", changes: ["Loading for 2"], willChangeCount: 1, didChangeCount: 1)
        observer.reset()
        
        changeString("Loaded 2!")
        verify(value: "Loaded 2!", changes: ["Loaded 2!"], willChangeCount: 0, didChangeCount: 0)
        observer.reset()
        
        changeString("Loaded 2 again!")
        verify(value: "Loaded 2 again!", changes: ["Loaded 2 again!"], willChangeCount: 0, didChangeCount: 0)
        observer.reset()
        
        removal()
    }
    
    func testFlatMapLifetime() {
        let intSource = PipeSignal<Int>()
        let intProperty = intSource.property()
        
        var stringValue = "Nothing"
        var stringSource: PipeSignal<String>? = nil
        func changeString(_ newValue: String) {
            stringValue = newValue
            stringSource!.notifyValueChanging(newValue)
        }
        
        var mapped: AsyncReadableProperty<String>? = intProperty.flatMap{ value -> AsyncReadableProperty<String> in
            stringValue = "Loading for \(value)"
            stringSource = PipeSignal<String>()
            stringSource!.onObserve = { observer in
                observer.notifyValueChanging(stringValue)
            }
            return stringSource!.property()
        }
        weak var weakMapped: AsyncReadableProperty<String>? = mapped
        
        XCTAssertNotNil(weakMapped)
        XCTAssertEqual(weakMapped!.value, nil)
        
        intSource.notifyValueChanging(1)
        XCTAssertEqual(weakMapped!.value, "Loading for 1")
        
        // Verify that property weakly observes its underlying signal and does not leave dangling strong references
        // that prevent the property from being deinitialized
        mapped = nil
        XCTAssertNil(weakMapped)
    }
    
    func testZip() {
        let source1 = PipeSignal<Bool>()
        let source2 = PipeSignal<Bool>()
        
        let property1 = AsyncReadableProperty(signal: source1)
        let property2 = AsyncReadableProperty(signal: source2)
        
        let zipped = zip(property1, property2)
        let observer = TestObserver<(Bool, Bool)>()
        
        func verify(value: (Bool, Bool)?, changes: [(Bool, Bool)], willChangeCount: Int, didChangeCount: Int, file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(zipped.value?.0, value?.0, file: file, line: line)
            XCTAssertEqual(zipped.value?.1, value?.1, file: file, line: line)
            XCTAssertEqual(observer.changes.map{ $0.0 }, changes.map{ $0.0 }, file: file, line: line)
            XCTAssertEqual(observer.changes.map{ $0.1 }, changes.map{ $0.1 }, file: file, line: line)
            XCTAssertEqual(observer.willChangeCount, willChangeCount, file: file, line: line)
            XCTAssertEqual(observer.didChangeCount, didChangeCount, file: file, line: line)
        }
        
        verify(value: nil, changes: [], willChangeCount: 0, didChangeCount: 0)
        
        // TODO: Use PipeSignal.onObserve to simulate initial async load when first observer attached
        let removal = observer.observe(zipped.signal)
        verify(value: nil, changes: [], willChangeCount: 0, didChangeCount: 0)
        
        source1.notifyValueChangedAsync(true)
        verify(value: nil, changes: [], willChangeCount: 1, didChangeCount: 1)
        
        source2.notifyValueChangedAsync(false)
        verify(value: (true, false), changes: [(true, false)], willChangeCount: 2, didChangeCount: 2)
        
        source2.notifyValueChangedAsync(true)
        verify(value: (true, true), changes: [(true, false), (true, true)], willChangeCount: 3, didChangeCount: 3)
        
        removal()
    }
    
    func testZipLifetime() {
        let source1 = PipeSignal<Bool>()
        let source2 = PipeSignal<Bool>()
        
        let property1 = AsyncReadableProperty(signal: source1)
        let property2 = AsyncReadableProperty(signal: source2)
        
        var zipped: AsyncReadableProperty<(Bool, Bool)>? = zip(property1, property2)
        weak var weakZipped: AsyncReadableProperty<(Bool, Bool)>? = zipped
        
        XCTAssertNotNil(weakZipped)
        XCTAssertEqual(weakZipped!.value?.0, nil)
        XCTAssertEqual(weakZipped!.value?.1, nil)
        
        source1.notifyValueChanging(true)
        XCTAssertEqual(weakZipped!.value?.0, nil)
        XCTAssertEqual(weakZipped!.value?.1, nil)

        source2.notifyValueChanging(false)
        XCTAssertEqual(weakZipped!.value?.0, true)
        XCTAssertEqual(weakZipped!.value?.1, false)

        // Verify that property weakly observes its underlying signal and does not leave dangling strong references
        // that prevent the property from being deinitialized
        zipped = nil
        XCTAssertNil(weakZipped)
    }
    
    func testZipAndMapLifetime() {
        let source1 = PipeSignal<Bool>()
        let source2 = PipeSignal<Bool>()
        
        let property1 = AsyncReadableProperty(signal: source1)
        let property2 = AsyncReadableProperty(signal: source2)
        
        var mapped: AsyncReadableProperty<String>? =
            zip(property1, property2)
                .map{ "\($0.0) \($0.1)" }
        weak var weakMapped: AsyncReadableProperty<String>? = mapped
        
        XCTAssertNotNil(weakMapped)
        XCTAssertEqual(weakMapped!.value, nil)
        
        source1.notifyValueChanging(true)
        XCTAssertEqual(weakMapped!.value, nil)
        
        source2.notifyValueChanging(false)
        XCTAssertEqual(weakMapped!.value, "true false")
        
        // Verify that property weakly observes its underlying signal and does not leave dangling strong references
        // that prevent the property from being deinitialized
        mapped = nil
        XCTAssertNil(weakMapped)
    }
    
//    func testZipWithNonNilInitialValues() {
//        let (property1, notify1) = AsyncReadableProperty<Bool>.pipe(initialValue: false)
//        let (property2, notify2) = AsyncReadableProperty<String>.pipe(initialValue: "foo")
//        let zipped = zip(property1, property2)
//        var changeObserved = false
//        _ = zipped.signal.observe({ _ in changeObserved = true })
////        zipped.start()
//        
//        XCTAssertEqual(zipped.value?.0, false)
//        XCTAssertEqual(zipped.value?.1, "foo")
//        XCTAssertEqual(changeObserved, false)
//        changeObserved = false
//        
//        notify1.valueChanging(true, transient: false)
//        XCTAssertEqual(zipped.value?.0, true)
//        XCTAssertEqual(zipped.value?.1, "foo")
//        XCTAssertEqual(changeObserved, true)
//        changeObserved = false
//        
//        notify2.valueChanging("bar", transient: false)
//        XCTAssertEqual(zipped.value?.0, true)
//        XCTAssertEqual(zipped.value?.1, "bar")
//        XCTAssertEqual(changeObserved, true)
//        changeObserved = false
//    }
    
    func testNot() {
        let source = PipeSignal<Bool>()
        let property = AsyncReadableProperty(signal: source)
        let mapped = !property
        let observer = BoolObserver()
        
        func verify(value: Bool?, changes: [Bool], willChangeCount: Int, didChangeCount: Int, file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(mapped.value, value, file: file, line: line)
            XCTAssertEqual(observer.changes, changes, file: file, line: line)
            XCTAssertEqual(observer.willChangeCount, willChangeCount, file: file, line: line)
            XCTAssertEqual(observer.didChangeCount, didChangeCount, file: file, line: line)
        }
        
        verify(value: nil, changes: [], willChangeCount: 0, didChangeCount: 0)
        
        // TODO: Use PipeSignal.onObserve to simulate initial async load when first observer attached
        let removal = observer.observe(mapped.signal)
        verify(value: nil, changes: [], willChangeCount: 0, didChangeCount: 0)
        
        source.notifyValueChangedAsync(false)
        verify(value: true, changes: [true], willChangeCount: 1, didChangeCount: 1)
        
        source.notifyValueChangedAsync(true)
        verify(value: false, changes: [true, false], willChangeCount: 2, didChangeCount: 2)
        
        removal()
    }
}
