//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

public enum TransactionResult {
    case commit
    case rollback
    case retry
}

public protocol StoredDatabase {
    func storedRelation(forName name: String) -> StoredRelation?
    
    func transaction<Return>(_ transactionFunction: (Void) -> (Return, TransactionResult)) -> Result<Return, RelationError>
    func resultNeedsRetry<T>(_ result: Result<T, RelationError>) -> Bool
}
