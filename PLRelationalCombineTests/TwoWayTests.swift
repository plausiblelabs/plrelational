//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import Combine
import PLRelational
@testable import PLRelationalCombine

private final class FakeViewModel: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    private let pets: Relation
    private var cancellableBag = Set<AnyCancellable>()

    @TwoWay var petName: String = "" {
        willSet {
            Swift.print("petName willSet: \(newValue)")
        }
    }

    init() {
        pets = MakeRelation(
            ["id", "name", "friendly", "age", "pulse"],
            [1,    "cat",  1,          5,     2.0],
            [2,    "cat",  1,          5,     2.0])

        pets
            .project("name")
            .bind(to: \._petName, on: self, strategy: oneString)
            .store(in: &cancellableBag)
    }
    
    func updatePetName(_ s: String) {
        pets.asyncUpdate(true, newValues: ["name": s])
    }
}

class TwoWayTests: CombineTestCase {
    
    func testViewModel() {
        let vm = FakeViewModel()
        
        var willChangeExpectation = XCTestExpectation(description: "will change")
        let cancelWillChange = vm.objectWillChange.sink { _ in
            willChangeExpectation.fulfill()
        }
        XCTAssertNotNil(cancelWillChange)
        
        var didChangeExpectation = XCTestExpectation(description: "did change")
        didChangeExpectation.expectedFulfillmentCount = 2
        var values: [String] = []
        let cancelDidChange = vm.$petName.sink(
            receiveCompletion: { _ in
                XCTFail("No completion is expected")
            },
            receiveValue: { value in
                print("RECEIVED \(value)")
                values.append(value)
                didChangeExpectation.fulfill()
            }
        )
        XCTAssertNotNil(cancelDidChange)

        // Verify that initial query produces "cat"
        wait(for: [willChangeExpectation, didChangeExpectation], timeout: 5.0)
        XCTAssertEqual(values, ["", "cat"])

        // Verify that new value is published after relation is updated
        willChangeExpectation = XCTestExpectation(description: "will change")
        didChangeExpectation = XCTestExpectation(description: "did change")
        vm.updatePetName("kat")
        wait(for: [willChangeExpectation, didChangeExpectation], timeout: 5.0)
        XCTAssertEqual(values, ["", "cat", "kat"])

        // TODO: Set value via setter and verify result

        cancelDidChange.cancel()
        cancelWillChange.cancel()
    }
}
