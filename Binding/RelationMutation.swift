//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import libRelational

extension Relation {
    /// Performs a synchronous update using a single RelationValue.
    public func updateValue(_ value: RelationValue) {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        let row: Row = [attr: value]
        var mutableRelation = self
        _ = mutableRelation.update(true, newValues: row)
    }
    
    /// Performs a synchronous update using a single string value.
    public func updateString(_ value: String) {
        updateValue(RelationValue(value))
    }
    
    /// Performs a synchronous update using a single optional string value.
    public func updateNullableString(_ value: String?) {
        let rv: RelationValue
        if let value = value {
            rv = RelationValue(value)
        } else {
            rv = .null
        }
        updateValue(rv)
    }
    
    /// Performs a synchronous update using a single integer value.
    public func updateInteger(_ value: Int64) {
        updateValue(RelationValue(value))
    }
    
    /// Performs a synchronous update using a single boolean value (converted to 0 for `false` and 1 for `true`).
    public func updateBoolean(_ value: Bool) {
        updateValue(RelationValue(Int64(value ? 1 : 0)))
    }
}

extension Relation {
    /// Performs an asynchronous update using a single RelationValue.
    public func asyncUpdateValue(_ value: RelationValue) {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        let row: Row = [attr: value]
        self.asyncUpdate(true, newValues: row)
    }
    
    /// Performs an asynchronous update using a single string value.
    public func asyncUpdateString(_ value: String) {
        asyncUpdateValue(RelationValue(value))
    }
    
    /// Performs an asynchronous update using a single optional string value.
    public func asyncUpdateNullableString(_ value: String?) {
        let rv: RelationValue
        if let value = value {
            rv = RelationValue(value)
        } else {
            rv = .null
        }
        asyncUpdateValue(rv)
    }
    
    /// Performs an asynchronous update using a single integer value.
    public func asyncUpdateInteger(_ value: Int64) {
        asyncUpdateValue(RelationValue(value))
    }
    
    /// Performs an asynchronous update using a single boolean value (converted to 0 for `false` and 1 for `true`).
    public func asyncUpdateBoolean(_ value: Bool) {
        asyncUpdateValue(RelationValue(Int64(value ? 1 : 0)))
    }
}

extension MutableRelation {
    /// Replaces the rows in this relation (synchronously) by performing a delete-all followed by an add for each row.
    public func replaceRows(_ rows: [Row]) {
        var mutableRelation = self
        _ = mutableRelation.delete(true)
        for row in rows {
            _ = mutableRelation.add(row)
        }
    }

    /// Replaces the rows in this relation (synchronously) by performing a delete-all followed by an add for each value.
    public func replaceValues(_ values: [RelationValue]) {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        var mutableRelation = self
        _ = mutableRelation.delete(true)
        for id in values {
            _ = mutableRelation.add([attr: id])
        }
    }
}

extension TransactionalRelation {
    /// Replaces the rows in this relation (asynchronously) by performing a delete-all followed by an add for each row.
    public func asyncReplaceRows(_ rows: [Row]) {
        self.asyncDelete(true)
        for row in rows {
            self.asyncAdd(row)
        }
    }

    /// Replaces the rows in this relation (asynchronously) by performing a delete-all followed by an add for each value.
    public func asyncReplaceValues(_ values: [RelationValue]) {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        self.asyncDelete(true)
        for id in values {
            self.asyncAdd([attr: id])
        }
    }
}
