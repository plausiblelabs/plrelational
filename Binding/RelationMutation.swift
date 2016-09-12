//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import libRelational

extension Relation {
    /// Performs a synchronous update using a single RelationValue.
    public func updateValue(value: RelationValue) {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        let row: Row = [attr: value]
        var mutableRelation = self
        mutableRelation.update(true, newValues: row)
    }
    
    /// Performs a synchronous update using a single string value.
    public func updateString(value: String) {
        updateValue(RelationValue(value))
    }
    
    /// Performs a synchronous update using a single optional string value.
    public func updateNullableString(value: String?) {
        let rv: RelationValue
        if let value = value {
            rv = RelationValue(value)
        } else {
            rv = .NULL
        }
        updateValue(rv)
    }
    
    /// Performs a synchronous update using a single integer value.
    public func updateInteger(value: Int64) {
        updateValue(RelationValue(value))
    }
    
    /// Performs a synchronous update using a single boolean value (converted to 0 for `false` and 1 for `true`).
    public func updateBoolean(value: Bool) {
        updateValue(RelationValue(Int64(value ? 1 : 0)))
    }
}

extension Relation {
    /// Performs an asynchronous update using a single RelationValue.
    public func asyncUpdateValue(value: RelationValue) {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        let row: Row = [attr: value]
        self.asyncUpdate(true, newValues: row)
    }
    
    /// Performs an asynchronous update using a single string value.
    public func asyncUpdateString(value: String) {
        asyncUpdateValue(RelationValue(value))
    }
    
    /// Performs an asynchronous update using a single optional string value.
    public func asyncUpdateNullableString(value: String?) {
        let rv: RelationValue
        if let value = value {
            rv = RelationValue(value)
        } else {
            rv = .NULL
        }
        asyncUpdateValue(rv)
    }
    
    /// Performs an asynchronous update using a single integer value.
    public func asyncUpdateInteger(value: Int64) {
        asyncUpdateValue(RelationValue(value))
    }
    
    /// Performs an asynchronous update using a single boolean value (converted to 0 for `false` and 1 for `true`).
    public func asyncUpdateBoolean(value: Bool) {
        asyncUpdateValue(RelationValue(Int64(value ? 1 : 0)))
    }
}

extension MutableRelation {
    /// Replaces the rows in this relation (synchronously) by performing a delete-all followed by an add for each row.
    public func replaceRows(rows: [Row]) {
        var mutableRelation = self
        mutableRelation.delete(true)
        for row in rows {
            mutableRelation.add(row)
        }
    }

    /// Replaces the rows in this relation (synchronously) by performing a delete-all followed by an add for each value.
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

extension TransactionalDatabase.TransactionalRelation {
    /// Replaces the rows in this relation (asynchronously) by performing a delete-all followed by an add for each row.
    public func asyncReplaceRows(rows: [Row]) {
        self.asyncDelete(true)
        for row in rows {
            self.asyncAdd(row)
        }
    }

    /// Replaces the rows in this relation (asynchronously) by performing a delete-all followed by an add for each value.
    public func asyncReplaceValues(values: [RelationValue]) {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        self.asyncDelete(true)
        for id in values {
            self.asyncAdd([attr: id])
        }
    }
}
