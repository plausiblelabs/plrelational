//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import PLRelational

extension Relation {
    /// Generates all non-error rows in the relation.
    public func okRows() -> AnyIterator<Row> {
        return AnyIterator(self.rows().lazy.flatMap{ $0.ok }.makeIterator())
    }
    
    /// Returns a set of all values for the single attribute, built from one transformed value for each non-error row
    /// in the given set.
    public func allValues<V: Hashable>(_ rows: AnyIterator<Row>, _ transform: @escaping (RelationValue) -> V?) -> Set<V> {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        return Set(rows
            .flatMap{transform($0[attr])})
    }

    /// Returns a set of all values for the single attribute, built from one RelationValue for each non-error row
    /// in the given set.
    public func allValues(_ rows: AnyIterator<Row>) -> Set<RelationValue> {
        return allValues(rows, { $0 })
    }

    /// Returns a set of all values for the single attribute, built from one transformed value for each non-error row
    /// in the relation.
    public func allValues<V: Hashable>(_ transform: @escaping (RelationValue) -> V?) -> Set<V> {
        return allValues(okRows(), transform)
    }

    /// Returns a set of all values, built from one transformed value for each row in the given set.
    public func allValuesFromRows<V: Hashable>(_ rows: AnyIterator<Row>, _ transform: @escaping (Row) -> V?) -> Set<V> {
        return Set(rows.flatMap{transform($0)})
    }

    /// Returns a set of all values, built from one transformed value for each non-error row in the relation.
    public func allValuesFromRows<V: Hashable>(_ transform: @escaping (Row) -> V?) -> Set<V> {
        return allValuesFromRows(okRows(), transform)
    }

    /// Returns a set of all RelationValues for the single attribute in the relation.
    public func allValues() -> Set<RelationValue> {
        return allValues{ $0 }
    }
    
    /// Returns some transformed value for the single attribute if there are one or more rows, or nil
    /// if there are no non-error rows.
    public func anyValue<V>(_ transform: (RelationValue) -> V?) -> V? {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        if let row = self.rows().next()?.ok {
            return transform(row[attr])
        } else {
            return nil
        }
    }
    
    /// Returns a RelationValue for the single attribute if there are one or more rows, or nil
    /// if there are no non-error rows.
    public func anyValue() -> RelationValue? {
        return anyValue{ $0 }
    }
    
    /// Returns a single row if there is exactly one row in the given set, otherwise returns nil.
    public func oneRow(_ rows: AnyIterator<Row>) -> Row? {
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
    public func oneRow() -> Row? {
        return oneRow(okRows())
    }

    /// Returns a single transformed value if there is exactly one row in the given set, otherwise returns nil.
    public func oneValueFromRow<V>(_ rows: AnyIterator<Row>, _ transform: @escaping (Row) -> V?) -> V? {
        return oneRow(rows).flatMap{ transform($0) }
    }

    /// Returns a single transformed value if there is exactly one row in the relation, otherwise returns nil.
    public func oneValueFromRow<V>(_ transform: @escaping (Row) -> V?) -> V? {
        return oneValueFromRow(okRows(), transform)
    }

    /// Returns a single transformed value if there is exactly one row in the given set, otherwise returns nil.
    public func oneValueFromRow<V>(_ rows: AnyIterator<Row>, _ transform: @escaping (Row) -> V?, orDefault defaultValue: V) -> V {
        return oneValueFromRow(okRows(), transform) ?? defaultValue
    }

    /// Returns a single transformed value if there is exactly one row in the relation, otherwise returns
    /// the given default value.
    public func oneValueFromRow<V>(_ transform: @escaping (Row) -> V?, orDefault defaultValue: V) -> V {
        return oneValueFromRow(okRows(), transform, orDefault: defaultValue)
    }

    /// Returns a single transformed value if there is exactly one row in the given set, otherwise returns nil.
    public func oneValue<V>(_ rows: AnyIterator<Row>, _ transform: @escaping (RelationValue) -> V?) -> V? {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        return oneRow(rows).flatMap{ transform($0[attr]) }
    }

    /// Returns a single transformed value if there is exactly one row in the relation, otherwise returns nil.
    public func oneValue<V>(_ transform: @escaping (RelationValue) -> V?) -> V? {
        return oneValue(okRows(), transform)
    }
    
    /// Returns a single RelationValue if there is exactly one row in the relation, otherwise returns nil.
    public func oneValueOrNil() -> RelationValue? {
        return oneValue{ $0 }
    }

    /// Returns a single RelationValue if there is exactly one row in the relation, otherwise returns nil.
    public func oneValueOrNil(_ rows: AnyIterator<Row>) -> RelationValue? {
        return oneValue(rows, { $0 })
    }

    /// Returns a a single string value if there is exactly one row in the given set, otherwise returns nil.
    public func oneStringOrNil(_ rows: AnyIterator<Row>) -> String? {
        return oneValue(rows, { $0.get() })
    }
    
    /// Returns a single string value if there is exactly one row in the given set, otherwise returns
    /// an empty string.
    public func oneString(_ rows: AnyIterator<Row>) -> String {
        return oneStringOrNil(rows) ?? ""
    }

    /// Returns a single string value if there is exactly one row in the relation, otherwise returns nil.
    public func oneStringOrNil() -> String? {
        return oneStringOrNil(okRows())
    }
    
    /// Returns a single string value if there is exactly one row in the relation, otherwise returns
    /// an empty string.
    public func oneString() -> String {
        return oneString(okRows())
    }

    /// Returns a single integer value if there is exactly one row in the given set, otherwise returns nil.
    public func oneIntegerOrNil(_ rows: AnyIterator<Row>) -> Int64? {
        return oneValue(rows, { $0.get() })
    }

    /// Returns a single integer value if there is exactly one row in the given set, otherwise returns zero.
    public func oneInteger(_ rows: AnyIterator<Row>) -> Int64 {
        return oneIntegerOrNil(rows) ?? 0
    }

    /// Returns a single integer value if there is exactly one row in the relation, otherwise returns nil.
    public func oneIntegerOrNil() -> Int64? {
        return oneIntegerOrNil(okRows())
    }
    
    /// Returns a single integer value if there is exactly one row in the relation, otherwise returns zero.
    public func oneInteger() -> Int64 {
        return oneInteger(okRows())
    }

    /// Returns a single double value if there is exactly one row in the given set, otherwise returns nil.
    public func oneDoubleOrNil(_ rows: AnyIterator<Row>) -> Double? {
        return oneValue(rows, { $0.get() })
    }

    /// Returns a single double value if there is exactly one row in the given set, otherwise returns zero.
    public func oneDouble(_ rows: AnyIterator<Row>) -> Double {
        return oneDoubleOrNil(rows) ?? 0.0
    }
    
    /// Returns a single double value if there is exactly one row in the relation, otherwise returns nil.
    public func oneDoubleOrNil() -> Double? {
        return oneDoubleOrNil(okRows())
    }
    
    /// Returns a single double value if there is exactly one row in the relation, otherwise returns zero.
    public func oneDouble() -> Double {
        return oneDouble(okRows())
    }

    /// Returns a single boolean value if there is exactly one row in the given set, otherwise returns nil.
    public func oneBoolOrNil(_ rows: AnyIterator<Row>) -> Bool? {
        return oneValue(rows, { $0.boolValue })
    }
    
    /// Returns a single boolean value if there is exactly one row in the given set, otherwise returns false.
    public func oneBool(_ rows: AnyIterator<Row>) -> Bool {
        return oneBoolOrNil(rows) ?? false
    }

    /// Returns a single boolean value if there is exactly one row in the relation, otherwise returns nil.
    public func oneBoolOrNil() -> Bool? {
        return oneBoolOrNil(okRows())
    }
    
    /// Returns a single boolean value if there is exactly one row in the relation, otherwise returns false.
    public func oneBool() -> Bool {
        return oneBool(okRows())
    }
    
    /// Returns a single blob value if there is exactly one row in the given set, otherwise returns nil.
    public func oneBlobOrNil(_ rows: AnyIterator<Row>) -> [UInt8]? {
        return oneValue(rows, { $0.get() })
    }
    
    /// Returns a single blob value if there is exactly one row in the given set, otherwise returns
    /// an empty array.
    public func oneBlob(_ rows: AnyIterator<Row>) -> [UInt8] {
        return oneBlobOrNil(rows) ?? []
    }
    
    /// Returns a single blob value if there is exactly one row in the relation, otherwise returns nil.
    public func oneBlobOrNil() -> [UInt8]? {
        return oneBlobOrNil(okRows())
    }
    
    /// Returns a single blob value if there is exactly one row in the relation, otherwise returns
    /// an empty array.
    public func oneBlob() -> [UInt8] {
        return oneBlob(okRows())
    }
    
    /// Returns a CommonValue that indicates whether there are zero, one, or multiple rows in the relation.
    public func commonValue<V>(_ transform: (RelationValue) -> V?) -> CommonValue<V> {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        let rows = self.rows()
        if let row = rows.next()?.ok {
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
}
