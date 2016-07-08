//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation


/// A class which can manage an entire group of queries, to share work and perform them asynchronously.
/// In order to keep every single Relation client from needing to be aware of this, we make it global-ish,
/// with one per-thread instance (created when needed).
public class QueryManager {
    private var pendingQueries: [(Relation, Result<Set<Row>, RelationError> -> Void)] = []
    
    private var executionTimer: CFRunLoopTimer?
    
    /// Register a query to be run asynchronously. The callback will be invoked each time new rows are
    /// available, or when an error occurs. If no error occurs, the final callback is invoked with an
    /// empty set of rows to signal that execution has completed. The callback is invoked on the same
    /// thread, when the runloop is in a common mode.
    public func registerQuery(relation: Relation, callback: Result<Set<Row>, RelationError> -> Void) {
        pendingQueries.append((relation, callback))
        
        if executionTimer == nil {
            executionTimer = CFRunLoopTimerCreateWithHandler(nil, 0, 0, 0, 0, { _ in
                self.execute()
            })
            CFRunLoopAddTimer(CFRunLoopGetCurrent(), executionTimer, kCFRunLoopCommonModes)
        }
    }
    
    private func execute() {
        CFRunLoopTimerInvalidate(executionTimer)
        executionTimer = nil
        
        let queries = pendingQueries
        pendingQueries = []
        
        for (relation, callback) in queries {
            for result in relation.bulkRows() {
                switch result {
                case .Ok(let rows):
                    if !rows.isEmpty {
                        callback(result)
                    }
                case .Err:
                    callback(result)
                    return
                }
            }
            callback(.Ok([]))
        }
    }
}

extension QueryManager {
    public static var currentManager: QueryManager {
        struct Static {
            static let threadDictionaryKey = "\(QueryManager.self) \(NSUUID().UUIDString)"
        }
        
        if let manager = NSThread.currentThread().threadDictionary[Static.threadDictionaryKey] as? QueryManager {
            return manager
        } else {
            let manager = QueryManager()
            NSThread.currentThread().threadDictionary[Static.threadDictionaryKey] = manager
            return manager
        }
    }
}
