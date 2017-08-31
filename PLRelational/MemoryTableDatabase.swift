//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

/// A minimal implementation of the `StoredDatabase` protocol that allows `MemoryTableRelation` to be used
/// with `TransactionalDatabase`.
public class MemoryTableDatabase: StoredDatabase {
    
    private var relations: Mutexed<[String: MemoryTableRelation]>

    public init(relations: [String: MemoryTableRelation] = [:]) {
        relations.forEach({ _ = $1.setDebugName($0) })
        self.relations = Mutexed(relations)
    }
    
    public subscript(name: String) -> StoredRelation? {
        return storedRelation(forName: name)
    }
    
    public func storedRelation(forName name: String) -> StoredRelation? {
        return relations.withValue({ $0[name] })
    }
    
    public func createRelation(_ name: String, scheme: Scheme) -> MemoryTableRelation {
        let relation = MemoryTableRelation(scheme: scheme)
        _ = relation.setDebugName(name)
        relations.withMutableValue({ $0[name] = relation })
        return relation
    }
    
    public func transaction<Return>(_ transactionFunction: (Void) -> (Return, TransactionResult)) -> Result<Return, RelationError> {
        return .Ok(transactionFunction().0)
    }
    
    public func resultNeedsRetry<T>(_ result: Result<T, RelationError>) -> Bool {
        return false
    }
}
