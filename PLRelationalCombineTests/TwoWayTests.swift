//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest
import Combine
import PLRelational
@testable import PLRelationalCombine

class TestOneStringStrategy: TwoWayStrategy {
    typealias Value = String

    private let relation: Relation
    private let initiator: InitiatorTag
    
    public let reader: TwoWayReader<String>
    public lazy var writer: TwoWayWriter<String> = {
        TwoWayWriter(
            willSet: {
                self.willSetOldValues.append($0)
                self.willSetNewValues.append($1)
            },
            didSet: {
                self.didSetValues.append($0)
                self.relation.asyncUpdateString($0, initiator: self.initiator)
            },
            commit: {
                self.commitValues.append($0)
                self.relation.asyncUpdateString($0, initiator: self.initiator)
            }
        )
    }()
    
    public var willSetOldValues: [String] = []
    public var willSetNewValues: [String] = []
    public var didSetValues: [String] = []
    public var commitValues: [String] = []

    init(_ relation: Relation, _ initiator: InitiatorTag) {
        self.relation = relation
        self.initiator = initiator
        
        self.reader = TwoWayReader(defaultValue: "", valueFromRows: { rows in
            relation.extractOneString(from: AnyIterator(rows.makeIterator()))
        })
    }
    
    func reset() {
        willSetOldValues = []
        willSetNewValues = []
        didSetValues = []
        commitValues = []
    }
}

private final class FakeViewModel: ObservableObject {
    let objectWillChange = ObjectWillChangePublisher()
    
    let pets: Relation
    private var cancellableBag = Set<AnyCancellable>()

    var typeStrategy: TestOneStringStrategy!
    var nameStrategy: TestOneStringStrategy!
    var noteStrategy: TestOneStringStrategy!

    @TwoWay(onSet: .commit) var petType: String = "initial type"
    @TwoWay(onSet: .update) var petName: String = "initial name"
    @TwoWay(onSet: .noop) var petNote: String = "initial note"

    init() {
        pets = MakeRelation(
            ["id", "type", "name", "note"],
            [1,    "cat",  "pete", "friendly"])

        pets
            .project("type")
            .bind(to: \._petType, on: self, strategy: { (r, i) -> TestOneStringStrategy in
                let s = TestOneStringStrategy(r, i)
                self.typeStrategy = s
                return s
            })
            .store(in: &cancellableBag)
        
        pets
            .project("name")
            .bind(to: \._petName, on: self, strategy: { (r, i) -> TestOneStringStrategy in
                let s = TestOneStringStrategy(r, i)
                self.nameStrategy = s
                return s
            })
            .store(in: &cancellableBag)
        
        pets
            .project("note")
            .bind(to: \._petNote, on: self, strategy: { (r, i) -> TestOneStringStrategy in
                let s = TestOneStringStrategy(r, i)
                self.noteStrategy = s
                return s
            })
            .store(in: &cancellableBag)
    }
    
    deinit {
        cancellableBag.forEach{ $0.cancel() }
    }
    
    func updatePet(type: String, name: String, note: String) {
        pets.asyncUpdate(true, newValues: ["type": type, "name": name, "note": note], initiator: nil)
    }
    
    func commitPetNote() {
        _petNote.commit()
    }
}

class TwoWayTests: CombineTestCase {
    
    func testBehaviors() {
        let vm = FakeViewModel()

        // Observe the objectWillChange publisher
        var willChange = false
        let cancelWillChange = vm.objectWillChange.sink { _ in
            willChange = true
        }
        
        // Observe the published values
        var types: [String] = []
        var names: [String] = []
        var notes: [String] = []
        let cancelTypes = vm.$petType.sink{ types.append($0) }
        let cancelNames = vm.$petName.sink{ names.append($0) }
        let cancelNotes = vm.$petNote.sink{ notes.append($0) }

        func reset() {
            willChange = false
            types = []
            vm.typeStrategy.reset()
            names = []
            vm.nameStrategy.reset()
            notes = []
            vm.noteStrategy.reset()
        }
        
        func verify(_ strategy: TestOneStringStrategy,
                    _ willSetOldValues: [String],
                    _ willSetNewValues: [String],
                    _ didSetValues: [String],
                    _ commitValues: [String],
                    file: StaticString = #file, line: UInt = #line)
        {
            XCTAssertEqual(strategy.willSetOldValues, willSetOldValues, file: file, line: line)
            XCTAssertEqual(strategy.willSetNewValues, willSetNewValues, file: file, line: line)
            XCTAssertEqual(strategy.didSetValues, didSetValues, file: file, line: line)
            XCTAssertEqual(strategy.commitValues, commitValues, file: file, line: line)
        }
        
        func verify(_ expected: Relation, file: StaticString = #file, line: UInt = #line) {
            AssertEqual(vm.pets, expected, file: file, line: line)
        }

        do {
            // Verify initial values (should be the same as the initial value for the @TwoWay, since
            // the initial query will not have completed yet)
            XCTAssertEqual(vm.petType, "initial type")
            XCTAssertEqual(vm.petName, "initial name")
            XCTAssertEqual(vm.petNote, "initial note")

            // Verify the initial published values
            XCTAssertEqual(willChange, false)
            XCTAssertEqual(types, ["initial type"])
            XCTAssertEqual(names, ["initial name"])
            XCTAssertEqual(notes, ["initial note"])

            // Verify that wrappedValues were not mutated
            verify(vm.typeStrategy, [], [], [], [])
            verify(vm.nameStrategy, [], [], [], [])
            verify(vm.noteStrategy, [], [], [], [])
            
            // Verify the underlying relation
            verify(MakeRelation(
                ["id", "type", "name", "note"],
                [1,    "cat",  "pete", "friendly"]))
        }

        do {
            // Wait for the initial relation queries to complete
            reset()
            awaitIdle()

            // Verify that the values are updated once the initial relation queries have completed
            XCTAssertEqual(vm.petType, "cat")
            XCTAssertEqual(vm.petName, "pete")
            XCTAssertEqual(vm.petNote, "friendly")
            
            // Verify that the new values are published
            XCTAssertEqual(willChange, true)
            XCTAssertEqual(types, ["cat"])
            XCTAssertEqual(names, ["pete"])
            XCTAssertEqual(notes, ["friendly"])

            // Verify that wrappedValues were not mutated
            verify(vm.typeStrategy, [], [], [], [])
            verify(vm.nameStrategy, [], [], [], [])
            verify(vm.noteStrategy, [], [], [], [])
            
            // Verify the underlying relation
            verify(MakeRelation(
                ["id", "type", "name", "note"],
                [1,    "cat",  "pete", "friendly"]))
        }

        do {
            // Change the underlying relation (this simulates a change that was initiated by an outside
            // party, i.e., not initiated by the control that is bound to the property)
            reset()
            vm.updatePet(type: "dog", name: "peter", note: "funny")
            awaitIdle()
            
            // Verify that the property values are updated once the relation observers are notified
            XCTAssertEqual(vm.petType, "dog")
            XCTAssertEqual(vm.petName, "peter")
            XCTAssertEqual(vm.petNote, "funny")
            
            // Verify that the new values are published
            XCTAssertEqual(willChange, true)
            XCTAssertEqual(types, ["dog"])
            XCTAssertEqual(names, ["peter"])
            XCTAssertEqual(notes, ["funny"])

            // Verify that wrappedValues were not mutated
            verify(vm.typeStrategy, [], [], [], [])
            verify(vm.nameStrategy, [], [], [], [])
            verify(vm.noteStrategy, [], [], [], [])
            
            // Verify the underlying relation
            verify(MakeRelation(
                ["id", "type", "name",  "note"],
                [1,    "dog",  "peter", "funny"]))
        }
        
        do {
            // Change `petType` and verify its commit-on-set behavior
            reset()
            vm.petType = "bird"
            awaitIdle()

            // Verify that the `petType` property value is updated
            XCTAssertEqual(vm.petType, "bird")
            XCTAssertEqual(vm.petName, "peter")
            XCTAssertEqual(vm.petNote, "funny")

            // Verify that the new `petType` value is published
            XCTAssertEqual(willChange, true)
            XCTAssertEqual(types, ["bird"])
            XCTAssertEqual(names, [])
            XCTAssertEqual(notes, [])

            // `petType` was declared with `commit` behavior, so verify that the commit function
            // was called
            verify(vm.typeStrategy, ["dog"], ["bird"], [], ["bird"])
            verify(vm.nameStrategy, [], [], [], [])
            verify(vm.noteStrategy, [], [], [], [])
            
            // Verify the underlying relation
            verify(MakeRelation(
                ["id", "type", "name",  "note"],
                [1,    "bird", "peter", "funny"]))
        }

        do {
            // Change `petName` and verify its update-on-set behavior
            reset()
            vm.petName = "fred"
            awaitIdle()

            // Verify that the `petName` property value is updated
            XCTAssertEqual(vm.petType, "bird")
            XCTAssertEqual(vm.petName, "fred")
            XCTAssertEqual(vm.petNote, "funny")

            // Verify that the new `petName` value is published
            XCTAssertEqual(willChange, true)
            XCTAssertEqual(types, [])
            XCTAssertEqual(names, ["fred"])
            XCTAssertEqual(notes, [])

            // `petName` was declared with `update` behavior, so verify that the update function
            // was called
            verify(vm.typeStrategy, [], [], [], [])
            verify(vm.nameStrategy, ["peter"], ["fred"], ["fred"], [])
            verify(vm.noteStrategy, [], [], [], [])

            // Verify the underlying relation
            verify(MakeRelation(
                ["id", "type", "name", "note"],
                [1,    "bird", "fred", "funny"]))
        }

        do {
            // Change `petNote` and verify its noop-on-set behavior
            reset()
            vm.petNote = "weird"
            awaitIdle()

            // Verify that the `petNote` value is updated
            XCTAssertEqual(vm.petType, "bird")
            XCTAssertEqual(vm.petName, "fred")
            XCTAssertEqual(vm.petNote, "weird")

            // Verify that the new `petNote` value is published
            XCTAssertEqual(willChange, true)
            XCTAssertEqual(types, [])
            XCTAssertEqual(names, [])
            XCTAssertEqual(notes, ["weird"])

            // `petNote` was declared with `noop` behavior, so verify that didSet/commit
            // were not called
            verify(vm.typeStrategy, [], [], [], [])
            verify(vm.nameStrategy, [], [], [], [])
            verify(vm.noteStrategy, ["funny"], ["weird"], [], [])

            // Verify the underlying relation (`note` should not be updated, because we
            // haven't updated or committed the value)
            verify(MakeRelation(
                ["id", "type", "name", "note"],
                [1,    "bird", "fred", "funny"]))
        }
        
        do {
            // Commit `petNote` and verify that the relation is finally updated
            reset()
            vm.commitPetNote()
            awaitIdle()

            // Verify that the property values are unchanged
            XCTAssertEqual(vm.petType, "bird")
            XCTAssertEqual(vm.petName, "fred")
            XCTAssertEqual(vm.petNote, "weird")

            // Verify that no new values are published
            XCTAssertEqual(willChange, false)
            XCTAssertEqual(types, [])
            XCTAssertEqual(names, [])
            XCTAssertEqual(notes, [])

            // Verify that just the commit function was called
            verify(vm.typeStrategy, [], [], [], [])
            verify(vm.nameStrategy, [], [], [], [])
            verify(vm.noteStrategy, [], [], [], ["weird"])

            // Verify the underlying relation; `note` should now be updated
            verify(MakeRelation(
                ["id", "type", "name", "note"],
                [1,    "bird", "fred", "weird"]))
        }

        cancelWillChange.cancel()
        cancelTypes.cancel()
        cancelNames.cancel()
        cancelNotes.cancel()
    }
}
