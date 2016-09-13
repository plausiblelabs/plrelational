//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import libRelational

// A not-so-optimal `flatMap` for lazy sequences, borrowed from:
//   https://github.com/apple/swift-evolution/blob/master/proposals/0008-lazy-flatmap-for-optionals.md
extension LazySequenceProtocol {
    
    func flatMap<T>(_ transform: (Elements.Iterator.Element) -> T?)
        -> LazyMapSequence<LazyFilterSequence<LazyMapSequence<Elements, T?>>, T> {
            return self
                .map(transform)
                .filter { opt in opt != nil }
                .map { notNil in notNil! }
    }
}

extension Relation {
    /// Generates all non-error rows in the relation.
    public var okRows: AnyIterator<Row> {
        return AnyIterator(self.rows().lazy.flatMap{ $0.ok }.makeIterator())
    }
    
    /// Resolves to a set of all values for the single attribute, built from one transformed value for each non-error row
    /// in the given set.
    public func allValues<V: Hashable>(_ rows: AnyIterator<Row>, _ transform: @escaping (RelationValue) -> V?) -> Set<V> {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        return Set(rows
            .flatMap{transform($0[attr])})
    }

    /// Resolves to a set of all values for the single attribute, built from one RelationValue for each non-error row
    /// in the given set.
    public func allValues(_ rows: AnyIterator<Row>) -> Set<RelationValue> {
        return allValues(rows, { $0 })
    }

    /// Resolves to a set of all values for the single attribute, built from one transformed value for each non-error row
    /// in the relation.
    public func allValues<V: Hashable>(_ transform: (RelationValue) -> V?) -> Set<V> {
        return allValues(okRows, transform)
    }

    /// Resolves to a set of all values, built from one transformed value for each non-error row in the relation.
    public func allValuesFromRows<V: Hashable>(_ transform: @escaping (Row) -> V?) -> Set<V> {
        return Set(okRows.flatMap{transform($0)})
    }

    /// Resolves to a set of all RelationValues for the single attribute in the relation.
    public var allValues: Set<RelationValue> {
        return allValues{ $0 }
    }
    
    /// Resolves to some transformed value for the single attribute if there are one or more rows, or nil
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
    
    /// Resolves to some RelationValue for the single attribute if there are one or more rows, or nil
    /// if there are no non-error rows.
    public var anyValue: RelationValue? {
        return anyValue{ $0 }
    }
    
    /// Resolves to a single row if there is exactly one row in the given set, otherwise resolves
    /// to nil.
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
    
    /// Resolves to a single row if there is exactly one row in the relation, otherwise resolves
    /// to nil.
    public var oneRow: Row? {
        return oneRow(okRows)
    }

    /// Resolves to a single transformed value if there is exactly one row in the given set, otherwise resolves
    /// to nil.
    public func oneValueFromRow<V>(_ rows: AnyIterator<Row>, _ transform: @escaping (Row) -> V?) -> V? {
        return oneRow(rows).flatMap{ transform($0) }
    }

    /// Resolves to a single transformed value if there is exactly one row in the relation, otherwise resolves
    /// to nil.
    public func oneValueFromRow<V>(_ transform: @escaping (Row) -> V?) -> V? {
        return oneValueFromRow(okRows, transform)
    }

    /// Resolves to a single transformed value if there is exactly one row in the given set, otherwise resolves
    /// to the given default value.
    public func oneValueFromRow<V>(_ rows: AnyIterator<Row>, _ transform: @escaping (Row) -> V?, orDefault defaultValue: V) -> V {
        return oneValueFromRow(okRows, transform) ?? defaultValue
    }

    /// Resolves to a single transformed value if there is exactly one row in the relation, otherwise resolves
    /// to the given default value.
    public func oneValueFromRow<V>(_ transform: @escaping (Row) -> V?, orDefault defaultValue: V) -> V {
        return oneValueFromRow(okRows, transform, orDefault: defaultValue)
    }

    /// Resolves to a single transformed value if there is exactly one row in the given set, otherwise resolves
    /// to nil.
    public func oneValue<V>(_ rows: AnyIterator<Row>, _ transform: @escaping (RelationValue) -> V?) -> V? {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        return oneRow(rows).flatMap{ transform($0[attr]) }
    }

    /// Resolves to a single transformed value if there is exactly one row in the relation, otherwise resolves
    /// to nil.
    public func oneValue<V>(_ transform: (RelationValue) -> V?) -> V? {
        return oneValue(okRows, transform)
    }
    
    /// Resolves to a single RelationValue if there is exactly one row in the relation, otherwise resolves
    /// to nil.
    public var oneValue: RelationValue? {
        return oneValue{ $0 }
    }

    /// Resolves to a single string value if there is exactly one row in the given set, otherwise resolves
    /// to nil.
    public func oneStringOrNil(_ rows: AnyIterator<Row>) -> String? {
        return oneValue(rows, { $0.get() })
    }
    
    /// Resolves to a single string value if there is exactly one row in the given set, otherwise resolves
    /// to an empty string.
    public func oneString(_ rows: AnyIterator<Row>) -> String {
        return oneStringOrNil(rows) ?? ""
    }

    /// Resolves to a single string value if there is exactly one row in the relation, otherwise resolves
    /// to nil.
    public var oneStringOrNil: String? {
        return oneStringOrNil(okRows)
    }
    
    /// Resolves to a single string value if there is exactly one row in the relation, otherwise resolves
    /// to an empty string.
    public var oneString: String {
        return oneString(okRows)
    }

    /// Resolves to a single integer value if there is exactly one row in the given set, otherwise resolves
    /// to nil.
    public func oneIntegerOrNil(_ rows: AnyIterator<Row>) -> Int64? {
        return oneValue(rows, { $0.get() })
    }

    /// Resolves to a single integer value if there is exactly one row in the given set, otherwise resolves
    /// to zero.
    public func oneInteger(_ rows: AnyIterator<Row>) -> Int64 {
        return oneIntegerOrNil(rows) ?? 0
    }

    /// Resolves to a single integer value if there is exactly one row in the relation, otherwise resolves
    /// to nil.
    public var oneIntegerOrNil: Int64? {
        return oneIntegerOrNil(okRows)
    }
    
    /// Resolves to a single integer value if there is exactly one row in the relation, otherwise resolves
    /// to zero.
    public var oneInteger: Int64 {
        return oneInteger(okRows)
    }

    /// Resolves to a single double value if there is exactly one row in the given set, otherwise resolves
    /// to nil.
    public func oneDoubleOrNil(_ rows: AnyIterator<Row>) -> Double? {
        return oneValue(rows, { $0.get() })
    }

    /// Resolves to a single double value if there is exactly one row in the given set, otherwise resolves
    /// to zero.
    public func oneDouble(_ rows: AnyIterator<Row>) -> Double {
        return oneDoubleOrNil(rows) ?? 0.0
    }
    
    /// Resolves to a single double value if there is exactly one row in the relation, otherwise resolves
    /// to nil.
    public var oneDoubleOrNil: Double? {
        return oneDoubleOrNil(okRows)
    }
    
    /// Resolves to a single double value if there is exactly one row in the relation, otherwise resolves
    /// to zero.
    public var oneDouble: Double {
        return oneDouble(okRows)
    }

    /// Resolves to a single boolean value if there is exactly one row in the given set, otherwise resolves
    /// to nil.
    public func oneBoolOrNil(_ rows: AnyIterator<Row>) -> Bool? {
        return oneValue(rows, { $0.boolValue })
    }
    
    /// Resolves to a single boolean value if there is exactly one row in the given set, otherwise resolves
    /// to false.
    public func oneBool(_ rows: AnyIterator<Row>) -> Bool {
        return oneBoolOrNil(rows) ?? false
    }

    /// Resolves to a single boolean value if there is exactly one row in the relation, otherwise resolves
    /// to nil.
    public var oneBoolOrNil: Bool? {
        return oneBoolOrNil(okRows)
    }
    
    /// Resolves to a single boolean value if there is exactly one row in the relation, otherwise resolves
    /// to false.
    public var oneBool: Bool {
        return oneBool(okRows)
    }
    
    /// Resolves to a CommonValue that indicates whether there are zero, one, or multiple rows in the relation.
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
