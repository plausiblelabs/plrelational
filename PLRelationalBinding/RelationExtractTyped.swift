//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import PLRelational

// TODO: All the V:Equatable overloads below exist only to carry type information so that the appropriate
// `isRepeat` function is selected.  It might be better to stop baking the `isRepeat` stuff into RelationSignal
// and instead have a generic `skipRepeats` combinator extension for SignalType to make it more of an opt-in thing.

extension Relation {
    
    // MARK: Signals
    
    /// Returns a Signal that delivers true when the set of rows is empty.
    public var empty: Signal<Bool> {
        // TODO: Make this a function that takes an optional initial value (instead
        // of forcing `initialValue: true`)
        return signal(initialValue: true, { $1.next() == nil })
    }

    /// Returns a Signal that delivers true when the set of rows is non-empty.
    public var nonEmpty: Signal<Bool> {
        return signal(initialValue: false, { $1.next() != nil })
    }
    
    /// Returns a Signal, sourced from this relation, that delivers all values for the single attribute.
    public func allValuesForSingleAttribute<V: Hashable>(_ transform: @escaping (RelationValue) -> V?) -> Signal<Set<V>> {
        return signal(initialValue: nil, { $0.extractAllValuesForSingleAttribute(from: $1, transform) })
    }
    
    /// Returns a Signal, sourced from this relation, that delivers a set of all RelationValues for the single attribute.
    public func allRelationValues() -> Signal<Set<RelationValue>> {
        return signal(initialValue: nil, { $0.extractAllRelationValues(from: $1) })
    }
    
    /// Returns a Signal, sourced from this relation, that delivers a set of all transformed values.
    public func allValues<V: Hashable>(_ transform: @escaping (Row) -> V?) -> Signal<Set<V>> {
        return signal(initialValue: nil, { $0.extractAllValues(from: $1, transform) })
    }

    /// Returns a Signal, sourced from this relation, that delivers a set of all strings for the
    /// single attribute.
    public func allStrings() -> Signal<Set<String>> {
        return signal(initialValue: nil, { $0.extractAllValuesForSingleAttribute(from: $1, { $0.get() }) })
    }

    /// Returns a Signal, sourced from this relation, that delivers a single row if there is exactly one,
    /// otherwise delivers nil.
    public func oneRow() -> Signal<Row?> {
        return signal(initialValue: nil, { $0.extractOneRow($1) })
    }
    
    /// Returns a Signal, sourced from this relation, that delivers a single transformed value if there is exactly
    /// one row, otherwise delivers nil.
    public func valueFromOneRow<V>(_ transform: @escaping (Row) -> V?) -> Signal<V?> {
        return signal(initialValue: nil, { $0.extractValueFromOneRow($1, transform) })
    }
    
    /// Returns a Signal, sourced from this relation, that delivers a single transformed value if there is exactly
    /// one row, otherwise delivers nil.
    public func valueFromOneRow<V: Equatable>(_ transform: @escaping (Row) -> V?) -> Signal<V?> {
        return signal(initialValue: nil, { $0.extractValueFromOneRow($1, transform) })
    }
    
    /// Returns a Signal, sourced from this relation, that delivers a single transformed value if there is exactly
    /// one row, otherwise delivers the given default value.
    public func valueFromOneRow<V>(_ transform: @escaping (Row) -> V?, orDefault defaultValue: V) -> Signal<V> {
        return signal(initialValue: nil, { $0.extractValueFromOneRow($1, transform, orDefault: defaultValue) })
    }
    
    /// Returns a Signal, sourced from this relation, that delivers a single transformed value if there is exactly
    /// one row, otherwise delivers the given default value.
    public func valueFromOneRow<V: Equatable>(_ transform: @escaping (Row) -> V?, orDefault defaultValue: V) -> Signal<V> {
        return signal(initialValue: nil, { $0.extractValueFromOneRow($1, transform, orDefault: defaultValue) })
    }
    
    /// Returns a Signal, sourced from this relation, that delivers a single transformed value if there is exactly
    /// one row, otherwise delivers nil.
    public func oneValueOrNil<V>(_ transform: @escaping (RelationValue) -> V?) -> Signal<V?> {
        return signal(initialValue: nil, { $0.extractOneValueOrNil(from: $1, transform) })
    }
    
    /// Returns a Signal, sourced from this relation, that delivers a single transformed value if there is exactly
    /// one row, otherwise delivers nil.
    public func oneValueOrNil<V: Equatable>(_ transform: @escaping (RelationValue) -> V?) -> Signal<V?> {
        return signal(initialValue: nil, { $0.extractOneValueOrNil(from: $1, transform) })
    }
    
    /// Returns a Signal, sourced from this relation, that delivers a single transformed value if there is exactly
    /// one row, otherwise delivers the given default value.
    public func oneValue<V>(_ transform: @escaping (RelationValue) -> V?, orDefault defaultValue: V, initialValue: V? = nil) -> Signal<V> {
        return signal(initialValue: initialValue, { $0.extractOneValue(from: $1, transform, orDefault: defaultValue) })
    }
    
    /// Returns a Signal, sourced from this relation, that delivers a single transformed value if there is exactly
    /// one row, otherwise delivers the given default value.
    public func oneValue<V: Equatable>(_ transform: @escaping (RelationValue) -> V?, orDefault defaultValue: V, initialValue: V? = nil) -> Signal<V> {
        return signal(initialValue: initialValue, { $0.extractOneValue(from: $1, transform, orDefault: defaultValue) })
    }
    
    /// Returns a Signal, sourced from this relation, that delivers a single RelationValue if there is exactly
    /// one row, otherwise delivers nil.
    public func oneRelationValueOrNil() -> Signal<RelationValue?> {
        return signal(initialValue: nil, { $0.extractOneRelationValueOrNil(from: $1) })
    }
    
    /// Returns a Signal, sourced from this relation, that delivers a single string value if there is exactly
    /// one row, otherwise delivers nil.
    public func oneStringOrNil(initialValue: String?? = nil) -> Signal<String?> {
        return signal(initialValue: initialValue, { $0.extractOneStringOrNil(from: $1) })
    }
    
    /// Returns a Signal, sourced from this relation, that delivers a single string value if there is exactly
    /// one row, otherwise delivers an empty string.
    public func oneString(initialValue: String? = nil) -> Signal<String> {
        return signal(initialValue: initialValue, { $0.extractOneString(from: $1) })
    }
    
    /// Returns a Signal, sourced from this relation, that delivers a single integer value if there is exactly
    /// one row, otherwise delivers nil.
    public func oneIntegerOrNil(initialValue: Int64?? = nil) -> Signal<Int64?> {
        return signal(initialValue: initialValue, { $0.extractOneIntegerOrNil(from: $1) })
    }
    
    /// Returns a Signal, sourced from this relation, that delivers a single integer value if there is exactly
    /// one row, otherwise delivers zero.
    public func oneInteger(initialValue: Int64? = nil) -> Signal<Int64> {
        return signal(initialValue: initialValue, { $0.extractOneInteger(from: $1) })
    }
    
    /// Returns a Signal, sourced from this relation, that delivers a single double value if there is exactly
    /// one row, otherwise delivers nil.
    public func oneDoubleOrNil(initialValue: Double?? = nil) -> Signal<Double?> {
        return signal(initialValue: initialValue, { $0.extractOneDoubleOrNil(from: $1) })
    }
    
    /// Returns a Signal, sourced from this relation, that delivers a single double value if there is exactly
    /// one row, otherwise delivers zero.
    public func oneDouble(initialValue: Double? = nil) -> Signal<Double> {
        return signal(initialValue: nil, { $0.extractOneDouble(from: $1) })
    }
    
    /// Returns a Signal, sourced from this relation, that delivers a single boolean value if there is exactly
    /// one row, otherwise delivers nil.
    public func oneBoolOrNil(initialValue: Bool?? = nil) -> Signal<Bool?> {
        return signal(initialValue: initialValue, { $0.extractOneBoolOrNil(from: $1) })
    }
    
    /// Returns a Signal, sourced from this relation, that delivers a single boolean value if there is exactly
    /// one row, otherwise delivers false.
    public func oneBool(initialValue: Bool? = nil) -> Signal<Bool> {
        return signal(initialValue: initialValue, { $0.extractOneBool(from: $1) })
    }
    
    /// Returns a Signal, sourced from this relation, that delivers a single blob value if there is exactly
    /// one row, otherwise delivers nil.
    public func oneBlobOrNil(initialValue: [UInt8]?? = nil) -> Signal<[UInt8]?> {
        return signal(initialValue: initialValue, { $0.extractOneBlobOrNil(from: $1) })
    }
    
    /// Returns a Signal, sourced from this relation, that delivers a single blob value if there is exactly
    /// one row, otherwise delivers an empty array.
    public func oneBlob(initialValue: [UInt8]? = nil) -> Signal<[UInt8]> {
        return signal(initialValue: initialValue, { $0.extractOneBlob(from: $1) })
    }
    
    /// Returns a Signal, sourced from this relation, that delivers a CommonValue that indicates whether there
    /// are zero, one, or multiple rows.
    public func commonValue<V>(_ transform: @escaping (RelationValue) -> V?) -> Signal<CommonValue<V>> {
        return signal(initialValue: nil, { $0.extractCommonValue(from: $1, transform) })
    }
    
    // MARK: Extract all values
    
    /// Returns a set of all values for the single attribute, built from one transformed value for each non-error row
    /// in the given set.
    public func extractAllValuesForSingleAttribute<V: Hashable>(from rows: AnyIterator<Row>, _ transform: @escaping (RelationValue) -> V?) -> Set<V> {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        return Set(rows
            .compactMap{transform($0[attr])})
    }

    /// Returns a set of all values for the single attribute, built from one transformed value for each non-error row
    /// in the relation.
    public func extractAllValuesForSingleAttribute<V: Hashable>(_ transform: @escaping (RelationValue) -> V?) -> Set<V> {
        return extractAllValuesForSingleAttribute(from: okRows(), transform)
    }
    
    /// Returns a set of all RelationValues for the single attribute, built from one RelationValue for each non-error row
    /// in the given set.
    public func extractAllRelationValues(from rows: AnyIterator<Row>) -> Set<RelationValue> {
        return extractAllValuesForSingleAttribute(from: rows, { $0 })
    }

    /// Returns a set of all RelationValues for the single attribute in the relation.
    public func extractAllRelationValues() -> Set<RelationValue> {
        return extractAllRelationValues(from: okRows())
    }
    
    /// Returns a set of all values, built from one transformed value for each row in the given set.
    public func extractAllValues<V: Hashable>(from rows: AnyIterator<Row>, _ transform: @escaping (Row) -> V?) -> Set<V> {
        return Set(rows.compactMap{transform($0)})
    }

    /// Returns a set of all values, built from one transformed value for each non-error row in the relation.
    public func extractAllValues<V: Hashable>(_ transform: @escaping (Row) -> V?) -> Set<V> {
        return extractAllValues(from: okRows(), transform)
    }

    // MARK: Extract one row
    
    /// Returns a single row if there is exactly one row in the given set, otherwise returns nil.
    public func extractOneRow(_ rows: AnyIterator<Row>) -> Row? {
        if let row = rows.next() {
            if rows.next() == nil {
                return row
            } else {
                return nil
            }
        } else {
            return nil
        }
    }
    
    /// Returns a single row if there is exactly one row in the relation, otherwise returns nil.
    public func extractOneRow() -> Row? {
        return extractOneRow(okRows())
    }
    
    // MARK: Extract one value
    
    /// Returns a single transformed value if there is exactly one row in the given set, otherwise returns nil.
    public func extractValueFromOneRow<V>(_ rows: AnyIterator<Row>, _ transform: @escaping (Row) -> V?) -> V? {
        return extractOneRow(rows).flatMap{ transform($0) }
    }

    /// Returns a single transformed value if there is exactly one row in the relation, otherwise returns nil.
    public func extractValueFromOneRow<V>(_ transform: @escaping (Row) -> V?) -> V? {
        return extractValueFromOneRow(okRows(), transform)
    }

    /// Returns a single transformed value if there is exactly one row in the given set, otherwise returns nil.
    public func extractValueFromOneRow<V>(_ rows: AnyIterator<Row>, _ transform: @escaping (Row) -> V?, orDefault defaultValue: V) -> V {
        return extractValueFromOneRow(rows, transform) ?? defaultValue
    }

    /// Returns a single transformed value if there is exactly one row in the relation, otherwise returns
    /// the given default value.
    public func extractValueFromOneRow<V>(_ transform: @escaping (Row) -> V?, orDefault defaultValue: V) -> V {
        return extractValueFromOneRow(okRows(), transform, orDefault: defaultValue)
    }

    /// Returns a single transformed value if there is exactly one row in the given set, otherwise returns nil.
    public func extractOneValueOrNil<V>(from rows: AnyIterator<Row>, _ transform: @escaping (RelationValue) -> V?) -> V? {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        return extractValueFromOneRow(rows, { transform($0[attr]) })
    }

    /// Returns a single transformed value if there is exactly one row in the relation, otherwise returns nil.
    public func extractOneValueOrNil<V>(_ transform: @escaping (RelationValue) -> V?) -> V? {
        return extractOneValueOrNil(from: okRows(), transform)
    }

    /// Returns a single transformed value if there is exactly one row in the given set, otherwise returns the
    /// given default value.
    public func extractOneValue<V>(from rows: AnyIterator<Row>, _ transform: @escaping (RelationValue) -> V?, orDefault defaultValue: V) -> V {
        return extractOneValueOrNil(from: rows, transform) ?? defaultValue
    }

    /// Returns a single transformed value if there is exactly one row in the relation, otherwise returns the
    /// given default value.
    public func extractOneValue<V>(_ transform: @escaping (RelationValue) -> V?, orDefault defaultValue: V) -> V {
        return extractOneValue(from: okRows(), transform, orDefault: defaultValue)
    }

    /// Returns a single RelationValue if there is exactly one row in the given set, otherwise returns nil.
    public func extractOneRelationValueOrNil(from rows: AnyIterator<Row>) -> RelationValue? {
        return extractOneValueOrNil(from: rows, { $0 })
    }
    
    /// Returns a single RelationValue if there is exactly one row in the relation, otherwise returns nil.
    public func extractOneRelationValueOrNil() -> RelationValue? {
        return extractOneRelationValueOrNil(from: okRows())
    }

    // MARK: Extract one String

    /// Returns a a single string value if there is exactly one row in the given set, otherwise returns nil.
    public func extractOneStringOrNil(from rows: AnyIterator<Row>) -> String? {
        return extractOneValueOrNil(from: rows, { $0.get() })
    }

    /// Returns a single string value if there is exactly one row in the relation, otherwise returns nil.
    public func extractOneStringOrNil() -> String? {
        return extractOneStringOrNil(from: okRows())
    }
    
    /// Returns a single string value if there is exactly one row in the given set, otherwise returns
    /// an empty string.
    public func extractOneString(from rows: AnyIterator<Row>) -> String {
        return extractOneStringOrNil(from: rows) ?? ""
    }

    /// Returns a single string value if there is exactly one row in the relation, otherwise returns
    /// an empty string.
    public func extractOneString() -> String {
        return extractOneString(from: okRows())
    }

    // MARK: Extract one Integer

    /// Returns a single integer value if there is exactly one row in the given set, otherwise returns nil.
    public func extractOneIntegerOrNil(from rows: AnyIterator<Row>) -> Int64? {
        return extractOneValueOrNil(from: rows, { $0.get() })
    }

    /// Returns a single integer value if there is exactly one row in the relation, otherwise returns nil.
    public func extractOneIntegerOrNil() -> Int64? {
        return extractOneIntegerOrNil(from: okRows())
    }

    /// Returns a single integer value if there is exactly one row in the given set, otherwise returns zero.
    public func extractOneInteger(from rows: AnyIterator<Row>) -> Int64 {
        return extractOneIntegerOrNil(from: rows) ?? 0
    }
    
    /// Returns a single integer value if there is exactly one row in the relation, otherwise returns zero.
    public func extractOneInteger() -> Int64 {
        return extractOneInteger(from: okRows())
    }
    
    // MARK: Extract one Double

    /// Returns a single double value if there is exactly one row in the given set, otherwise returns nil.
    public func extractOneDoubleOrNil(from rows: AnyIterator<Row>) -> Double? {
        return extractOneValueOrNil(from: rows, { $0.get() })
    }

    /// Returns a single double value if there is exactly one row in the relation, otherwise returns nil.
    public func extractOneDoubleOrNil() -> Double? {
        return extractOneDoubleOrNil(from: okRows())
    }
    
    /// Returns a single double value if there is exactly one row in the given set, otherwise returns zero.
    public func extractOneDouble(from rows: AnyIterator<Row>) -> Double {
        return extractOneDoubleOrNil(from: rows) ?? 0.0
    }
    
    /// Returns a single double value if there is exactly one row in the relation, otherwise returns zero.
    public func extractOneDouble() -> Double {
        return extractOneDouble(from: okRows())
    }
    
    // MARK: Extract one Bool

    /// Returns a single boolean value if there is exactly one row in the given set, otherwise returns nil.
    public func extractOneBoolOrNil(from rows: AnyIterator<Row>) -> Bool? {
        return extractOneValueOrNil(from: rows, { $0.boolValue })
    }
    
    /// Returns a single boolean value if there is exactly one row in the relation, otherwise returns nil.
    public func extractOneBoolOrNil() -> Bool? {
        return extractOneBoolOrNil(from: okRows())
    }
    
    /// Returns a single boolean value if there is exactly one row in the given set, otherwise returns false.
    public func extractOneBool(from rows: AnyIterator<Row>) -> Bool {
        return extractOneBoolOrNil(from: rows) ?? false
    }
    
    /// Returns a single boolean value if there is exactly one row in the relation, otherwise returns false.
    public func extractOneBool() -> Bool {
        return extractOneBool(from: okRows())
    }

    // MARK: Extract one Blob

    /// Returns a single blob value if there is exactly one row in the given set, otherwise returns nil.
    public func extractOneBlobOrNil(from rows: AnyIterator<Row>) -> [UInt8]? {
        return extractOneValueOrNil(from: rows, { $0.get() })
    }
    
    /// Returns a single blob value if there is exactly one row in the relation, otherwise returns nil.
    public func extractOneBlobOrNil() -> [UInt8]? {
        return extractOneBlobOrNil(from: okRows())
    }
    
    /// Returns a single blob value if there is exactly one row in the given set, otherwise returns
    /// an empty array.
    public func extractOneBlob(from rows: AnyIterator<Row>) -> [UInt8] {
        return extractOneBlobOrNil(from: rows) ?? []
    }
    
    /// Returns a single blob value if there is exactly one row in the relation, otherwise returns
    /// an empty array.
    public func extractOneBlob() -> [UInt8] {
        return extractOneBlob(from: okRows())
    }
    
    // MARK: Extract CommonValue
    
    /// Returns a CommonValue that indicates whether there are zero, one, or multiple rows in the given set.
    public func extractCommonValue<V>(from rows: AnyIterator<Row>, _ transform: (RelationValue) -> V?) -> CommonValue<V> {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        if let row = rows.next() {
            if rows.next() == nil {
                if let value = transform(row[attr]) {
                    return .one(value)
                } else {
                    return .none
                }
            } else {
                return .multi
            }
        } else {
            return .none
        }
    }
    
    /// Returns a CommonValue that indicates whether there are zero, one, or multiple rows in the given set.
    public func extractCommonValue<V>(_ transform: (RelationValue) -> V?) -> CommonValue<V> {
        return extractCommonValue(from: okRows(), transform)
    }
    
    /// MARK: Row iterators
    
    /// Generates all non-error rows in the relation.
    public func okRows() -> AnyIterator<Row> {
        return AnyIterator(self.rows().lazy.compactMap{ $0.ok }.makeIterator())
    }
}
