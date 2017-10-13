//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import PLRelational

/// Base class for our identifier value types.  All of our identifiers use UUIDs
/// under the hood and we have conveniences for conversion to/from `RelationValue`.
class BaseID {
    fileprivate let uuid: String
    
    init() {
        self.uuid = UUID().uuidString
    }
    
    required init(_ stringValue: String) {
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
final class ItemID: BaseID {
    /// Shorthand for extracting an `ItemID` from an `Item` row.
    convenience init(_ row: Row) {
        self.init(row[Item.id.attribute])
    }
}

/// Identifier type for rows in the `Tag` relation.
final class TagID: BaseID {
    /// Shorthand for extracting a `TagID` from an `Tag` row.
    convenience init(_ row: Row) {
        self.init(row[Tag.id.attribute])
    }
}

/// Conforming to this protocol allows us to use `ItemID` and `TagID` directly
/// in row initializers and in select expressions without having to explicitly
/// convert to `RelationValue`.
extension BaseID: SelectExpressionConstantValue {}

extension TypedAttributeValue where Self: BaseID {
    static func make(from: RelationValue) -> Result<Self, RelationError> {
        return String.make(from: from).map(self.init)
    }
    
    var toRelationValue: RelationValue {
        return relationValue
    }
    
    var hashValue: Int {
        return uuid.hashValue
    }
    
    static func ==(lhs: Self, rhs: Self) -> Bool {
        return lhs.uuid == rhs.uuid
    }
}

extension ItemID: TypedAttributeValue {}
extension TagID: TypedAttributeValue {}

