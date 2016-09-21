//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

public class PlistDatabase: StoredDatabase {

    public enum RelationSpec { case
        file(name: String, path: String, scheme: Scheme),
        directory(name: String, path: String, scheme: Scheme, primaryKey: Attribute)
    }
    
    fileprivate var relations: Mutexed<[String: StoredRelation]>

    private init(relations: [String: StoredRelation]) {
        self.relations = Mutexed(relations)
    }
    
    public static func open(_ specs: [RelationSpec]) -> Result<PlistDatabase, RelationError> {
        // TODO
        return .Ok(PlistDatabase(relations: [:]))
    }
    
    public subscript(name: String) -> StoredRelation? {
        return storedRelation(forName: name)
    }

    public func storedRelation(forName name: String) -> StoredRelation? {
        return relations.withValue({ $0[name] })
    }
    
    public func transaction<Return>(_ transactionFunction: (Void) -> (Return, TransactionResult)) -> Result<Return, RelationError> {
        // TODO: Coordinate writes to minimize file I/O
        let result = transactionFunction()
        return .Ok(result.0)
    }
    
    public func resultNeedsRetry<T>(_ result: Result<T, RelationError>) -> Bool {
        return false
    }
}
