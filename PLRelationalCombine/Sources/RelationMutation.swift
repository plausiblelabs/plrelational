//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import PLRelational

extension Relation {
    
    // MARK: - Asynchronous updates
    
    /// Performs an asynchronous update using a single RelationValue.
    public func asyncUpdateValue(_ value: RelationValue, initiator: InitiatorTag? = nil) {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        let row: Row = [attr: value]
        self.asyncUpdate(true, newValues: row, initiator: initiator)
    }
    
    /// Performs an asynchronous update using a single string value.
    public func asyncUpdateString(_ value: String, initiator: InitiatorTag? = nil) {
        asyncUpdateValue(RelationValue(value), initiator: initiator)
    }
    
    /// Performs an asynchronous update using a single optional string value.
    public func asyncUpdateNullableString(_ value: String?, initiator: InitiatorTag? = nil) {
        let rv: RelationValue
        if let value = value {
            rv = RelationValue(value)
        } else {
            rv = .null
        }
        asyncUpdateValue(rv, initiator: initiator)
    }
    
    /// Performs an asynchronous update using a single integer value.
    public func asyncUpdateInteger(_ value: Int64, initiator: InitiatorTag? = nil) {
        asyncUpdateValue(RelationValue(value), initiator: initiator)
    }
    
    /// Performs an asynchronous update using a single boolean value (converted to 0 for `false` and 1 for `true`).
    public func asyncUpdateBoolean(_ value: Bool, initiator: InitiatorTag? = nil) {
        asyncUpdateValue(RelationValue(Int64(value ? 1 : 0)), initiator: initiator)
    }
}

extension MutableRelation {
    /// Replaces the rows in this relation (asynchronously) by performing a delete-all followed by an add for each row.
    public func asyncReplaceRows(_ rows: [Row], initiator: InitiatorTag? = nil) {
        self.asyncDelete(true, initiator: initiator)
        for row in rows {
            self.asyncAdd(row, initiator: initiator)
        }
    }

    /// Replaces the rows in this relation (asynchronously) by performing a delete-all followed by an add for each value.
    public func asyncReplaceValues(_ values: [RelationValue], initiator: InitiatorTag? = nil) {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        self.asyncDelete(true, initiator: initiator)
        for value in values {
            self.asyncAdd([attr: value], initiator: initiator)
        }
    }

    /// Replaces the rows in this relation (asynchronously) by performing a delete-all followed by an add if the given
    /// value is defined.
    public func asyncReplaceValue(_ value: RelationValue?, initiator: InitiatorTag? = nil) {
        precondition(self.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
        let attr = self.scheme.attributes.first!
        self.asyncDelete(true, initiator: initiator)
        if let value = value {
            self.asyncAdd([attr: value], initiator: initiator)
        }
    }

    /// Replaces the rows in this relation (asynchronously) by performing a delete-all followed by an add if the given
    /// string value is defined.
    public func asyncReplaceString(_ value: String?, initiator: InitiatorTag? = nil) {
        asyncReplaceValue(value.map{ RelationValue($0) })
    }

    /// Replaces the rows in this relation (asynchronously) by performing a delete-all followed by an add if the given
    /// integer value is defined.
    public func asyncReplaceInteger(_ value: Int64?, initiator: InitiatorTag? = nil) {
        asyncReplaceValue(value.map{ RelationValue($0) })
    }
}
