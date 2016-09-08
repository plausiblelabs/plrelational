//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

public protocol MutableRelation: Relation {
    mutating func add(_ row: Row) -> Result<Int64, RelationError>
    mutating func delete(_ query: SelectExpression) -> Result<Void, RelationError>
}

public protocol MutableSelectRelation: class, Relation {
    var selectExpression: SelectExpression { get set }
}
