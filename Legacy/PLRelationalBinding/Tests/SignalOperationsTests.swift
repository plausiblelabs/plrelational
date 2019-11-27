//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
@testable import PLRelationalBinding

class TestObserver<T> {
    var willChangeCount = 0
    var didChangeCount = 0
    var changes: [T] = []
    
    func observe(_ signal: Signal<T>) -> ObserverRemoval {
        return signal.observe{ event in
            switch event {
            case .beginPossibleAsyncChange:
                self.willChangeCount += 1

            case let .valueChanging(newValue, _):
                self.changes.append(newValue)

            case .endPossibleAsyncChange:
                self.didChangeCount += 1
            }
        }
    }
    
    func reset() {
        willChangeCount = 0
        didChangeCount = 0
        changes = []
    }
}

typealias StringObserver = TestObserver<String>
typealias BoolObserver = TestObserver<Bool>
typealias IntObserver = TestObserver<Int>

func verify<T: Equatable>(_ observer: TestObserver<T>, changes: [T], willChangeCount: Int, didChangeCount: Int, file: StaticString = #file, line: UInt = #line) {
    XCTAssertEqual(observer.changes, changes, file: file, line: line)
    XCTAssertEqual(observer.willChangeCount, willChangeCount, file: file, line: line)
    XCTAssertEqual(observer.didChangeCount, didChangeCount, file: file, line: line)
}

extension SignalObserver {
    /// Shorthand for `notifyBeginPossibleAsyncChange`, `notifyValueChanging` (transient=false), and `notifyEndPossibleAsyncChange` in series.
    public func notifyValueChangedAsync(_ value: T) {
        notifyBeginPossibleAsyncChange()
        notifyValueChanging(value, transient: false)
        notifyEndPossibleAsyncChange()
    }
}

extension SourceSignal {
    /// Shorthand for `notifyBeginPossibleAsyncChange`, `notifyValueChanging` (transient=false), and `notifyEndPossibleAsyncChange` in series.
    public func notifyValueChangedAsync(_ value: T) {
        notifyBeginPossibleAsyncChange()
        notifyValueChanging(value, transient: false)
        notifyEndPossibleAsyncChange()
    }
}

class SignalOperationsTests: BindingTestCase {
    
    private func verifyUnary<T, U: Equatable>(source: SourceSignal<T>, mapped: Signal<U>, values: [T], expected: [U], file: StaticString = #file, line: UInt = #line) {
        let observer = TestObserver<U>()
        
        let removal = observer.observe(mapped)
        verify(observer, changes: [], willChangeCount: 0, didChangeCount: 0, file: file, line: line)

        source.notifyValueChangedAsync(values[0])
        verify(observer, changes: [expected[0]], willChangeCount: 1, didChangeCount: 1, file: file, line: line)

        source.notifyValueChangedAsync(values[1])
        verify(observer, changes: [expected[0], expected[1]], willChangeCount: 2, didChangeCount: 2, file: file, line: line)
        
        removal()
    }
    
    private func verifyBinary<T1, T2, U: Equatable>(source1: SourceSignal<T1>, source2: SourceSignal<T2>, mapped: Signal<U>, values1: [T1], values2: [T2], expected: [U], file: StaticString = #file, line: UInt = #line) {
        let observer = TestObserver<U>()
        
        let removal = observer.observe(mapped)
        verify(observer, changes: [], willChangeCount: 0, didChangeCount: 0, file: file, line: line)
        
        source1.notifyValueChangedAsync(values1[0])
        verify(observer, changes: [], willChangeCount: 1, didChangeCount: 1, file: file, line: line)

        source2.notifyValueChangedAsync(values2[0])
        verify(observer, changes: [expected[0]], willChangeCount: 2, didChangeCount: 2, file: file, line: line)

        source1.notifyValueChangedAsync(values1[1])
        verify(observer, changes: [expected[0], expected[1]], willChangeCount: 3, didChangeCount: 3, file: file, line: line)
        
        removal()
    }

    func testMap() {
        let source = SourceSignal<Bool>()
        
        let mapped = source.map{ $0 ? 1 : 0 }
        
        verifyUnary(
            source: source,
            mapped: mapped,
            values: [true, false],
            expected: [1, 0]
        )
    }
    
    func testMapLifetime() {
        let source = PipeSignal<Int>()
        source.onObserve = { observer in
            observer.notifyValueChanging(0)
        }
        
        var mapped: Signal<String>? = source.map{ "\($0)" }
        weak var weakMapped: Signal<String>? = mapped
        
        XCTAssertNotNil(weakMapped)
        
        var mappedValue: String?
        let removal = mapped!.observeValueChanging{ newValue, _ in mappedValue = newValue }
        XCTAssertEqual(mappedValue, "0")
        
        source.notifyValueChanging(1)
        XCTAssertEqual(mappedValue, "1")

        removal()

        // Verify that mapped signal weakly observes its underlying signal and does not leave dangling strong references
        // that prevent the mapped signal from being deinitialized
        mapped = nil
        XCTAssertNil(weakMapped)
    }

    func testFlatMap() {
        let intSource = SourceSignal<Int>()
        
        var stringValue = "Nothing"
        var stringSource: PipeSignal<String>? = nil
        func changeString(_ newValue: String) {
            stringValue = newValue
            stringSource!.notifyValueChanging(newValue)
        }

        let mapped = intSource.flatMap{ value -> Signal<String> in
            stringValue = "Loading for \(value)"
            stringSource = PipeSignal<String>()
            stringSource!.onObserve = { observer in
                observer.notifyValueChanging(stringValue)
            }
            return stringSource!
        }
        
        let observer1 = TestObserver<String>()
        
        let removal1 = observer1.observe(mapped)
        verify(observer1, changes: [], willChangeCount: 0, didChangeCount: 0)
        
        intSource.notifyValueChangedAsync(1)
        verify(observer1, changes: ["Loading for 1"], willChangeCount: 1, didChangeCount: 1)
        observer1.reset()
        
        changeString("Loaded 1!")
        verify(observer1, changes: ["Loaded 1!"], willChangeCount: 0, didChangeCount: 0)
        observer1.reset()

        changeString("Loaded 1 again!")
        verify(observer1, changes: ["Loaded 1 again!"], willChangeCount: 0, didChangeCount: 0)
        observer1.reset()

        intSource.notifyValueChangedAsync(2)
        verify(observer1, changes: ["Loading for 2"], willChangeCount: 1, didChangeCount: 1)
        observer1.reset()
        
        changeString("Loaded 2!")
        verify(observer1, changes: ["Loaded 2!"], willChangeCount: 0, didChangeCount: 0)
        observer1.reset()
        
        changeString("Loaded 2 again!")
        verify(observer1, changes: ["Loaded 2 again!"], willChangeCount: 0, didChangeCount: 0)
        observer1.reset()

        let observer2 = TestObserver<String>()
        let removal2 = observer2.observe(mapped)
        verify(observer1, changes: [], willChangeCount: 0, didChangeCount: 0)
        verify(observer2, changes: ["Loaded 2 again!"], willChangeCount: 0, didChangeCount: 0)
        observer1.reset()
        observer2.reset()
        
        removal1()
        removal2()
    }
    
    func testFlatMapLifetime() {
        let intSource = SourceSignal<Int>()
        
        let stringSource = PipeSignal<String>()
        stringSource.onObserve = { observer in
            observer.notifyValueChanging("Loading!")
        }
        
        var mapped: Signal<String>? = intSource.flatMap{ value -> Signal<String> in
            return stringSource
        }
        weak var weakMapped: Signal<String>? = mapped
        
        XCTAssertNotNil(weakMapped)
        
        var mappedValue: String?
        let removal = mapped!.observeValueChanging{ newValue, _ in mappedValue = newValue }
        XCTAssertEqual(mappedValue, nil)
        
        intSource.notifyValueChanging(1)
        XCTAssertEqual(mappedValue, "Loading!")

        stringSource.notifyValueChanging("Loaded!")
        XCTAssertEqual(mappedValue, "Loaded!")

        removal()
        
        // Verify that mapped signal weakly observes its underlying signal and does not leave dangling strong references
        // that prevent the mapped signal from being deinitialized
        mapped = nil
        XCTAssertNil(weakMapped)
    }

    func testZip() {
        let source1 = SourceSignal<Bool>()
        let source2 = SourceSignal<Bool>()
        
        let zipped = zip(source1, source2)

        // TODO: Can use verifyBinary() for this if we pass a custom equality checking function for tuples
        
        let observer = TestObserver<(Bool, Bool)>()

        func verify(changes: [(Bool, Bool)], willChangeCount: Int = 0, didChangeCount: Int = 0, file: StaticString = #file, line: UInt = #line) {
            XCTAssertEqual(observer.changes.map{ $0.0 }, changes.map{ $0.0 }, file: file, line: line)
            XCTAssertEqual(observer.changes.map{ $0.1 }, changes.map{ $0.1 }, file: file, line: line)
            XCTAssertEqual(observer.willChangeCount, willChangeCount, file: file, line: line)
            XCTAssertEqual(observer.didChangeCount, didChangeCount, file: file, line: line)
        }
        
        let removal = observer.observe(zipped)
        verify(changes: [], willChangeCount: 0, didChangeCount: 0)
        
        source1.notifyValueChangedAsync(false)
        verify(changes: [], willChangeCount: 1, didChangeCount: 1)
        
        source2.notifyValueChangedAsync(true)
        verify(changes: [(false, true)], willChangeCount: 2, didChangeCount: 2)
        
        source1.notifyValueChangedAsync(true)
        verify(changes: [(false, true), (true, true)], willChangeCount: 3, didChangeCount: 3)
        
        removal()
    }
    
    func testNot() {
        let source = SourceSignal<Bool>()
        
        let mapped = not(source)

        verifyUnary(
            source: source,
            mapped: mapped,
            values: [true, false],
            expected: [false, true]
        )
    }
    
    func testOr() {
        let source1 = SourceSignal<Bool>()
        let source2 = SourceSignal<Bool>()
        
        let mapped = source1 *|| source2

        verifyBinary(
            source1: source1,
            source2: source2,
            mapped: mapped,
            values1: [false, true],
            values2: [false],
            expected: [false, true]
        )
    }
    
    func testAnd() {
        let source1 = SourceSignal<Bool>()
        let source2 = SourceSignal<Bool>()
        
        let mapped = source1 *&& source2
        
        verifyBinary(
            source1: source1,
            source2: source2,
            mapped: mapped,
            values1: [false, true],
            values2: [true],
            expected: [false, true]
        )
    }

    func testThen() {
        var count = 0
        let source = SourceSignal<Bool>()
        
        let then = source.then{ count += 1 }
        
        let removal = then.observeValueChanging{ _, _ in }
        XCTAssertEqual(count, 0)
        
        source.notifyValueChanging(false)
        XCTAssertEqual(count, 0)
        
        source.notifyValueChanging(true)
        XCTAssertEqual(count, 1)
        
        source.notifyValueChanging(true)
        XCTAssertEqual(count, 2)
        
        removal()
    }

    func testEq() {
        let source1 = SourceSignal<Bool>()
        let source2 = SourceSignal<Bool>()
        
        let mapped = source1 *== source2
        
        verifyBinary(
            source1: source1,
            source2: source2,
            mapped: mapped,
            values1: [false, true],
            values2: [true],
            expected: [false, true]
        )
    }
}
