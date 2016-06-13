//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

public struct RelationChange {
    public var added: Relation?
    public var removed: Relation?
}

extension RelationChange: CustomStringConvertible {
    public var description: String {
        func stringForRelation(r: Relation?) -> String {
            guard let r = r else { return "∅" }
            if r.isEmpty.ok ?? false { return "∅" }
            return "\n\(r.description)\n"
        }
        return "RelationChange added: \(stringForRelation(added)) removed: \(stringForRelation(removed))"
    }
}
