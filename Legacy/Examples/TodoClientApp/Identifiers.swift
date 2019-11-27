//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import PLRelational

/// Base class for our identifier value types.  All of our identifiers use UUIDs
/// under the hood and we have conveniences for conversion to/from `RelationValue`.
class BaseID {
    private let uuid: String
    
    init() {
        self.uuid = UUID().uuidString
    }
    
    init(_ stringValue: String) {
        self.uuid = stringValue
    }
    
    init(_ relationValue: RelationValue) {
        self.uuid = relationValue.get()!
    }
    
    var relationValue: RelationValue {
        return uuid.relationValue
    }
}

/// Identifier type for rows in the `Item` relation.
class ItemID: BaseID {
    /// Shorthand for extracting an `ItemID` from an `Item` row.
    convenience init(_ row: Row) {
        self.init(row[Item.id])
    }
}

/// Identifier type for rows in the `Tag` relation.
class TagID: BaseID {
    /// Shorthand for extracting a `TagID` from an `Tag` row.
    convenience init(_ row: Row) {
        self.init(row[Tag.id])
    }
}

/// Conforming to this protocol allows us to use `ItemID` and `TagID` directly
/// in row initializers and in select expressions without having to explicitly
/// convert to `RelationValue`.
extension BaseID: SelectExpressionConstantValue {}
