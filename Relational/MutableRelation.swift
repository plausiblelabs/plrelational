//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

public protocol MutableRelation: Relation {
    mutating func add(row: Row) -> Result<Int64, RelationError>
    mutating func delete(query: SelectExpression) -> Result<Void, RelationError>
}
