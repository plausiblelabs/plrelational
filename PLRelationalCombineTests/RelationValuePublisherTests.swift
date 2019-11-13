//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import Combine
import PLRelational
@testable import PLRelationalCombine

private final class FakeViewModel: ObservableObject {
    private let pets: Relation
    private var cancellableBag = Set<AnyCancellable>()

    @Published var petName: String = ""

    init() {
        pets = MakeRelation(
            ["id", "name", "friendly", "age", "pulse"],
            [1,    "cat",  1,          5,     2.0],
            [2,    "cat",  1,          5,     2.0])
        
        pets
            .project("name")
            .oneString()
            .replaceError(with: "OOPS")
            .assign(to: \.petName, on: self)
            .store(in: &cancellableBag)
    }
    
    func updatePetName(_ s: String) {
        pets.asyncUpdate(true, newValues: ["name": s])
    }
}

class RelationValuePublisherTests: CombineTestCase {

    // XXX
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
        
        cancelDidChange.cancel()
        cancelWillChange.cancel()
    }
    
    // TODO: Migrate other tests from RelationExtractTyped
    // TODO: Move this and other value extraction tests to separate file
    func testOneStringPublisher() {
        let r = MakeRelation(
            ["id", "name", "friendly", "age", "pulse"],
            [1,    "cat",  1,          5,     2.0],
            [2,    "cat",  1,          5,     2.0])
        
        let pub = r.project("name").oneString()
        
        var expectation = XCTestExpectation(description: self.debugDescription)
        var values: [String] = []
        let cancellable = pub.sink(
            receiveCompletion: { _ in
                XCTFail("No completion is expected")
            },
            receiveValue: { value in
                values.append(value)
                expectation.fulfill()
            }
        )
        XCTAssertNotNil(cancellable)

        // Verify that initial query produces "cat"
        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(values == ["cat"])

        // Verify that new value is published after relation is updated
        expectation = XCTestExpectation(description: self.debugDescription)
        _ = r.asyncUpdate(true, newValues: ["name": "kat"])
        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(values == ["cat", "kat"])

        // Verify that empty string is published after relation is updated to have multiple values
        expectation = XCTestExpectation(description: self.debugDescription)
        _ = r.asyncAdd(["id": 3, "name": "dog", "friendly": 0, "age": 6, "pulse": 3.0])
        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(values == ["cat", "kat", ""])
    }
    
    func testIgnoreInitiator() {
        let r = MakeRelation(
            ["id", "name", "friendly", "age", "pulse"],
            [1,    "cat",  1,          5,     2.0])
        
        let pub = r
            .project("name")
            .oneString()
            .ignoreInitiator("1")
        
        var values: [String] = []
        let cancellable = pub.sink(
            receiveCompletion: { _ in
                XCTFail("No completion is expected")
            },
            receiveValue: { value in
                values.append(value)
            }
        )
        XCTAssertNotNil(cancellable)

        // Verify that initial query produces "cat"
        awaitIdle()
        XCTAssertTrue(values == ["cat"])

        // Verify that new value is published after relation is updated (when no
        // initiator is provided)
        _ = r.asyncUpdate(true, newValues: ["name": "kat"])
        awaitIdle()
        XCTAssertTrue(values == ["cat", "kat"])

        // Verify that value is not published after relation is updated using the
        // ignored initiator tag
        _ = r.asyncUpdate(true, newValues: ["name": "qat"], initiator: "1")
        awaitIdle()
        XCTAssertTrue(values == ["cat", "kat"])
    }
}
