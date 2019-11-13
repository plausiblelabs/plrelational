//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

// This file is based on the `@Published` implementation from OpenCombine:
//   https://github.com/broadwaylamb/OpenCombine/blob/master/Sources/OpenCombine/Published.swift

import Foundation
import Combine
import PLRelational

/// TODO: Docs
public protocol TwoWayStrategy {
    /// TODO: Docs
    associatedtype Value

    /// TODO: Docs
    var reader: TwoWayReader<Value> { get }
    
    /// TODO: Docs
    var writer: TwoWayWriter<Value> { get }
}

/// TODO: Docs
public struct TwoWayReader<Value> {
    /// XXX:  Only used to replace errors from the underlying publisher with a default value;
    /// we should find a better solution that doesn't involve swallowing errors
    public let defaultValue: Value

    /// TODO: Docs
    public let valueFromRows: (Set<Row>) -> Value
    
    public init(defaultValue: Value, valueFromRows: @escaping (Set<Row>) -> Value) {
        self.defaultValue = defaultValue
        self.valueFromRows = valueFromRows
    }
}

/// TODO: Docs
public struct TwoWayWriter<Value> {
    /// Called before the underlying value is set via the `wrappedValue` setter.
    public let willSetWrappedValue: (_ oldValue: Value, _ newValue: Value) -> Void
    
    /// Called after the underlying value is set via the `wrappedValue` setter.
    public let didSetWrappedValue: (Value) -> Void
    
    /// Called when the new value is committed via the `commit` function.
    public let commitWrappedValue: (Value) -> Void

    public init(willSet: @escaping (_ oldValue: Value, _ newValue: Value) -> Void,
                didSet: @escaping (Value) -> Void,
                commit: @escaping (Value) -> Void)
    {
        self.willSetWrappedValue = willSet
        self.didSetWrappedValue = didSet
        self.commitWrappedValue = commit
    }

    public init(didSet: @escaping (Value) -> Void) {
        self.willSetWrappedValue = { _, _ in }
        self.didSetWrappedValue = didSet
        self.commitWrappedValue = { _ in }
    }
}

@propertyWrapper
public struct TwoWay<Value> {

    /// TODO: Docs
    var rawValue: Value {
        willSet {
            Swift.print("TwoWay: rawValue will set: \(newValue)")
            objectWillChange?.send()
            publisher?.subject.value = newValue
        }
    }
    
    public var wrappedValue: Value {
        get {
            return rawValue
        }
        set {
            Swift.print("TwoWay: wrappedValue will set: \(newValue)")
            writer?.willSetWrappedValue(rawValue, newValue)
            
            Swift.print("TwoWay: wrappedValue set: \(newValue)")
            rawValue = newValue

            // Note that we only set the external value (i.e., update the associated relation)
            // when the value has been set by the public `wrappedValue` setter; we don't set
            // the external value when the underlying `rawValue` is set, which is part of the
            // solution to avoiding feedback loops in two-way binding scenarios
            Swift.print("TwoWay: wrappedValue did set: \(newValue)")
            writer?.didSetWrappedValue(newValue)
        }
    }

    /// The property that can be accessed with the
    /// `$` syntax and allows access to the `Publisher`
    public var projectedValue: Publisher {
        mutating get {
            if let publisher = publisher {
                return publisher
            }
            let publisher = Publisher(rawValue)
            self.publisher = publisher
            return publisher
        }
    }

    /// The writer that is used to perform custom logic when the underlying value is set
    /// via the `wrappedValue` property.
    public var writer: TwoWayWriter<Value>?
    
    /// The publisher that is installed by `bind:to` and is used to emit a will-change event when
    /// the underlying value is about to change.
    public var objectWillChange: ObservableObjectPublisher?
    
    /// The publisher for this property (initialized lazily).
    private var publisher: Publisher?

    public init(wrappedValue: Value) {
        self.rawValue = wrappedValue
    }
    
    /// Commits the latest value by invoking the writer's `commitWrappedValue` function.
    public func commit() {
        writer?.commitWrappedValue(rawValue)
    }

    /// A publisher for properties marked with the `@TwoWay` attribute.
    public struct Publisher: Combine.Publisher {

        /// The kind of values published by this publisher.
        public typealias Output = Value

        /// The kind of errors this publisher might publish.
        ///
        /// Use `Never` if this `Publisher` does not publish errors.
        public typealias Failure = Never

        /// This function is called to attach the specified
        /// `Subscriber` to this `Publisher` by `subscribe(_:)`
        ///
        /// - SeeAlso: `subscribe(_:)`
        /// - Parameters:
        ///     - subscriber: The subscriber to attach to this `Publisher`.
        ///                   once attached it can begin to receive values.
        public func receive<Downstream: Subscriber>(subscriber: Downstream)
            where Downstream.Input == Value, Downstream.Failure == Never
        {
            subject.subscribe(subscriber)
        }

        fileprivate let subject: CurrentValueSubject<Value, Never>

        fileprivate init(_ output: Output) {
            subject = .init(output)
        }
    }
}

public struct OneValueStrategy<Value>: TwoWayStrategy {
    public let reader: TwoWayReader<Value>
    public let writer: TwoWayWriter<Value>
}

/// TODO: Docs
public func oneString(_ relation: Relation, _ initiator: InitiatorTag) -> OneValueStrategy<String> {
    let reader = TwoWayReader(defaultValue: "", valueFromRows: { rows in
        relation.extractOneString(from: AnyIterator(rows.makeIterator()))
    })
    let writer = TwoWayWriter(didSet: {
        relation.asyncUpdateString($0, initiator: initiator)
    })
    return OneValueStrategy(reader: reader, writer: writer)
}

public class UndoableOneValueStrategy<Value>: TwoWayStrategy {
    private let undoableDB: UndoableDatabase
    private let action: String
    private let relation: Relation
    private let updateFunc: (Value) -> Void
    
    public let reader: TwoWayReader<Value>
    public lazy var writer: TwoWayWriter<Value> = {
        return TwoWayWriter(
            willSet: { _, _ in
                if self.before == nil {
                    self.before = self.undoableDB.takeSnapshot()
                }
            },
            didSet: { newValue in
                self.updateFunc(newValue)
            },
            commit: { newValue in
                // TODO: Check whether value has changed?
                if let before = self.before {
                    self.undoableDB.performUndoableAction(self.action, before: before, {
                        self.updateFunc(newValue)
                    })
                    self.before = nil
                }
            }
        )
    }()

    private var before: TransactionalDatabaseSnapshot?

    public init(undoableDB: UndoableDatabase, action: String, relation: Relation,
         reader: TwoWayReader<Value>, updateFunc: @escaping (Value) -> Void)
    {
        self.undoableDB = undoableDB
        self.action = action
        self.relation = relation
        self.updateFunc = updateFunc
        self.reader = reader
    }
}

public extension UndoableDatabase {
    // TODO: Flag for controlling whether to call update on intermediate changes (vs commit on end)
    func oneString(_ action: String) -> (Relation, InitiatorTag) -> UndoableOneValueStrategy<String> {
        return { relation, initiator in
            precondition(relation.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
            let reader: TwoWayReader<String> = TwoWayReader(defaultValue: "", valueFromRows: { rows in
                relation.extractOneString(from: AnyIterator(rows.makeIterator()))
            })
            let update = { (newValue: String) in
                relation.asyncUpdateString(newValue, initiator: initiator)
            }
            return UndoableOneValueStrategy(undoableDB: self, action: action, relation: relation,
                                            reader: reader, updateFunc: update)
        }
    }

    func oneBool(_ action: String) -> (Relation, InitiatorTag) -> UndoableOneValueStrategy<Bool> {
        return { relation, initiator in
            precondition(relation.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
            let reader: TwoWayReader<Bool> = TwoWayReader(defaultValue: false, valueFromRows: { rows in
                relation.extractOneBool(from: AnyIterator(rows.makeIterator()))
            })
            let update = { (newValue: Bool) in
                relation.asyncUpdateBoolean(newValue, initiator: initiator)
            }
            return UndoableOneValueStrategy(undoableDB: self, action: action, relation: relation,
                                            reader: reader, updateFunc: update)
        }
    }
}

extension Relation {
    
    /// TODO: Docs
    public func bind<Root, Value, Strategy>(to keyPath: ReferenceWritableKeyPath<Root, TwoWay<Value>>,
                                            on object: Root,
                                            strategy strategyFunc: (Relation, InitiatorTag) -> Strategy) -> AnyCancellable
        where Root: ObservableObject, Root.ObjectWillChangePublisher == ObservableObjectPublisher,
              Strategy: TwoWayStrategy, Strategy.Value == Value
    {
        // Create a unique initiator tag
        let initiator = UUID().uuidString
        
        // Get the strategy that is sourced from this relation
        let strategy = strategyFunc(self, initiator)
        
        // Install the TwoWayWriter on the TwoWay wrapper, so that the underlying
        // relation is updated when a new value is set via the public setter
        object[keyPath: keyPath].writer = strategy.writer

        return RelationValuePublisher(relation: self, ignoreInitiator: initiator, rowsToValue: { strategy.reader.valueFromRows($1) })
            .replaceError(with: strategy.reader.defaultValue) // XXX
            .bind(to: keyPath, on: object)
    }
}
