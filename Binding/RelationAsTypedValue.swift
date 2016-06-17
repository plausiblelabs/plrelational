//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import libRelational

extension Relation {
    /// Resolves to a set of all values for the single attribute, built from one transformed value for each non-error row.
    public func allValues<V: Hashable>(transform: RelationValue -> V?) -> Set<V> {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        return Set(self.rows()
            .flatMap{$0.ok}
            .flatMap{transform($0[attr])})
    }
    
    /// Resolves to a set of all RelationValues for the single attribute.
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
    
    /// Resolves to a single row if there is exactly one row in the relation, otherwise resolves
    /// to nil.
    public var oneRow: Row? {
        let rows = self.rows()
        if let row = rows.next()?.ok {
            if rows.next() == nil {
                return row
            } else {
                return nil
            }
        } else {
            return nil
        }
    }
    
    /// Resolves to a single transformed value if there is exactly one row in the relation, otherwise resolves
    /// to nil.
    public func oneValue<V>(transform: Row -> V?) -> V? {
        return oneRow.flatMap{ transform($0) }
    }
    
    /// Resolves to a single transformed value if there is exactly one row in the relation, otherwise resolves
    /// to the given default value.
    public func oneValue<V>(transform: Row -> V?, orDefault defaultValue: V) -> V {
        return oneValue{ transform($0) } ?? defaultValue
    }
    
    /// Resolves to a single transformed value if there is exactly one row in the relation, otherwise resolves
    /// to nil.
    public func oneValue<V>(transform: RelationValue -> V?) -> V? {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        return oneRow.flatMap{ transform($0[attr]) }
    }
    
    /// Resolves to a single RelationValue if there is exactly one row in the relation, otherwise resolves
    /// to nil.
    public var oneValue: RelationValue? {
        return oneValue{ $0 }
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
