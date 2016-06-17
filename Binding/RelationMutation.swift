//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import libRelational

extension Relation {
    /// Performs an update using a single RelationValue.
    public func updateValue(value: RelationValue) {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        let row: Row = [attr: value]
        var mutableRelation = self
        mutableRelation.update(true, newValues: row)
    }
    
    /// Performs an update using a single string value.
    public func updateString(value: String) {
        updateValue(RelationValue(value))
    }
    
    /// Performs an update using a single optional string value.
    public func updateNullableString(value: String?) {
        let rv: RelationValue
        if let value = value {
            rv = RelationValue(value)
        } else {
            rv = .NULL
        }
        updateValue(rv)
    }
    
    /// Performs an update using a single integer value.
    public func updateInteger(value: Int64) {
        updateValue(RelationValue(value))
    }
    
    /// Performs an update using a single boolean value (converted to 0 for `false` and 1 for `true`).
    public func updateBoolean(value: Bool) {
        updateValue(RelationValue(Int64(value ? 1 : 0)))
    }
}

extension MutableRelation {
    /// Replaces the given values by performing a delete followed by an add for each value.
    public func replaceValues(values: [RelationValue]) {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        var mutableRelation = self
        mutableRelation.delete(true)
        for id in values {
            mutableRelation.add([attr: id])
        }
    }
}
