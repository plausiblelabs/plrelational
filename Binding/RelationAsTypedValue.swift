//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import libRelational

// A not-so-optimal `flatMap` for lazy sequences, borrowed from:
//   https://github.com/apple/swift-evolution/blob/master/proposals/0008-lazy-flatmap-for-optionals.md
extension LazySequenceType {
    @warn_unused_result
    func flatMap<T>(transform: Elements.Generator.Element -> T?)
        -> LazyMapSequence<LazyFilterSequence<LazyMapSequence<Elements, T?>>, T> {
            return self
                .map(transform)
                .filter { opt in opt != nil }
                .map { notNil in notNil! }
    }
}

extension Relation {
    /// Generates all non-error rows in the relation.
    public var okRows: AnyGenerator<Row> {
        return AnyGenerator(self.rows().lazy.flatMap{ $0.ok }.generate())
    }

    /// Resolves to a set of all values for the single attribute, built from one transformed value for each non-error row
    /// in the given set.
    public func allValues<V: Hashable>(rows: AnyGenerator<Row>, _ transform: RelationValue -> V?) -> Set<V> {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        return Set(rows
            .flatMap{transform($0[attr])})
    }

    /// Resolves to a set of all values for the single attribute, built from one RelationValue for each non-error row
    /// in the given set.
    public func allValues(rows: AnyGenerator<Row>) -> Set<RelationValue> {
        return allValues(rows, { $0 })
    }

    /// Resolves to a set of all values for the single attribute, built from one transformed value for each non-error row
    /// in the relation.
    public func allValues<V: Hashable>(transform: RelationValue -> V?) -> Set<V> {
        return allValues(okRows, transform)
    }
    
    /// Resolves to a set of all RelationValues for the single attribute in the relation.
    public var allValues: Set<RelationValue> {
        return allValues{ $0 }
    }
    
    /// Resolves to some transformed value for the single attribute if there are one or more rows, or nil
    /// if there are no non-error rows.
    public func anyValue<V>(transform: RelationValue -> V?) -> V? {
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
    public func oneRow(rows: AnyGenerator<Row>) -> Row? {
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
    
    /// Resolves to a single transformed value if there is exactly one row in the relation, otherwise resolves
    /// to nil.
    public func oneValueFromRow<V>(transform: Row -> V?) -> V? {
        return oneRow.flatMap{ transform($0) }
    }
    
    /// Resolves to a single transformed value if there is exactly one row in the relation, otherwise resolves
    /// to the given default value.
    public func oneValueFromRow<V>(transform: Row -> V?, orDefault defaultValue: V) -> V {
        return oneValueFromRow{ transform($0) } ?? defaultValue
    }

    /// Resolves to a single transformed value if there is exactly one row in the given set, otherwise resolves
    /// to nil.
    public func oneValue<V>(rows: AnyGenerator<Row>, _ transform: RelationValue -> V?) -> V? {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        return oneRow(rows).flatMap{ transform($0[attr]) }
    }

    /// Resolves to a single transformed value if there is exactly one row in the relation, otherwise resolves
    /// to nil.
    public func oneValue<V>(transform: RelationValue -> V?) -> V? {
        return oneValue(okRows, transform)
    }
    
    /// Resolves to a single RelationValue if there is exactly one row in the relation, otherwise resolves
    /// to nil.
    public var oneValue: RelationValue? {
        return oneValue{ $0 }
    }

    /// Resolves to a single string value if there is exactly one row in the given set, otherwise resolves
    /// to an empty string.
    public func oneString(rows: AnyGenerator<Row>) -> String {
        return oneValue(rows, { $0.get() }) ?? ""
    }

    /// Resolves to a single string value if there is exactly one row in the relation, otherwise resolves
    /// to an empty string.
    public var oneString: String {
        return oneValue{ $0.get() } ?? ""
    }
    
    /// Resolves to a single string value if there is exactly one row in the relation, otherwise resolves
    /// to nil.
    public var oneStringOrNil: String? {
        return oneValue{ $0.get() }
    }

    /// Resolves to a single integer value if there is exactly one row in the given set, otherwise resolves
    /// to zero.
    public func oneInteger(rows: AnyGenerator<Row>) -> Int64 {
        return oneValue(rows, { $0.get() }) ?? 0
    }

    /// Resolves to a single integer value if there is exactly one row in the relation, otherwise resolves
    /// to zero.
    public var oneInteger: Int64 {
        return oneValue{ $0.get() } ?? 0
    }
    
    /// Resolves to a single integer value if there is exactly one row in the relation, otherwise resolves
    /// to nil.
    public var oneIntegerOrNil: Int64? {
        return oneValue{ $0.get() }
    }
    
    /// Resolves to a single double value if there is exactly one row in the given set, otherwise resolves
    /// to zero.
    public func oneDouble(rows: AnyGenerator<Row>) -> Double {
        return oneValue(rows, { $0.get() }) ?? 0.0
    }
    
    /// Resolves to a single double value if there is exactly one row in the relation, otherwise resolves
    /// to zero.
    public var oneDouble: Double {
        return oneValue{ $0.get() } ?? 0.0
    }
    
    /// Resolves to a single double value if there is exactly one row in the relation, otherwise resolves
    /// to nil.
    public var oneDoubleOrNil: Double? {
        return oneValue{ $0.get() }
    }

    /// Resolves to a single boolean value if there is exactly one row in the relation, otherwise resolves
    /// to false.
    public var oneBool: Bool {
        return oneValue{ $0.boolValue } ?? false
    }
    
    /// Resolves to a single boolean value if there is exactly one row in the relation, otherwise resolves
    /// to nil.
    public var oneBoolOrNil: Bool? {
        return oneValue{ $0.boolValue }
    }
    
    /// Resolves to a CommonValue that indicates whether there are zero, one, or multiple rows in the relation.
    public func commonValue<V>(transform: RelationValue -> V?) -> CommonValue<V> {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        let rows = self.rows()
        if let row = rows.next()?.ok {
            if rows.next() == nil {
                if let value = transform(row[attr]) {
                    return .One(value)
                } else {
                    return .None
                }
            } else {
                return .Multi
            }
        } else {
            return .None
        }
    }
}
