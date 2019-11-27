//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

public struct RelationChange {
    public let added: Relation?
    public let removed: Relation?
    
    public init(added: Relation?, removed: Relation?) {
        self.added = added
        self.removed = removed
    }
}

extension RelationChange {
    public func copy() -> Result<RelationChange, RelationError> {
        let copiedAdded = added.map(ConcreteRelation.copyRelation)
        let copiedRemoved = removed.map(ConcreteRelation.copyRelation)
        
        return
            hoistOptional(copiedAdded)
                .combine(hoistOptional(copiedRemoved))
                .map({ RelationChange(added: $0, removed: $1) })
    }
}

extension RelationChange: CustomStringConvertible {
    public var description: String {
        func stringForRelation(_ r: Relation?) -> String {
            guard let r = r else { return "∅" }
            if r.isEmpty.ok ?? false { return "∅" }
            return "\n\(r.description)\n"
        }
        return "RelationChange added: \(stringForRelation(added)) removed: \(stringForRelation(removed))"
    }
}
