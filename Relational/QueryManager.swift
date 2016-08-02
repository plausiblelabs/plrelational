//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation


/// A class which can manage an entire group of queries, to share work and perform them asynchronously.
public class QueryManager {
    private var pendingQueries: [(Relation, Result<Set<Row>, RelationError> -> Void)] = []
    
    public init() {}
    
    /// Register a query to be run asynchronously. The callback will be invoked each time new rows are
    /// available, or when an error occurs. If no error occurs, the final callback is invoked with an
    /// empty set of rows to signal that execution has completed. The callback is invoked on the same
    /// thread, when the runloop is in a common mode.
    public func registerQuery(relation: Relation, callback: Result<Set<Row>, RelationError> -> Void) {
        pendingQueries.append((relation, callback))
    }
    
    public func execute() {
        let queries = pendingQueries
        pendingQueries = []
        
        dispatch_async(dispatch_get_global_queue(0, 0), {
            let planner = QueryPlanner(roots: queries)
            let runner = QueryRunner(planner: planner)
            
            while !runner.done {
                runner.pump()
            }
            
            if !runner.didError {
                for (_, callback) in queries {
                    callback(.Ok([]))
                }
            }
        })
    }
}

/// A per-thread version of QueryManager which automatically executes registered queries on the next runloop cycle.
public final class RunloopQueryManager: QueryManager, PerThreadInstance {
    private var executionTimer: CFRunLoopTimer?
    
    public override func registerQuery(relation: Relation, callback: Result<Set<Row>, RelationError> -> Void) {
        let runloop = CFRunLoopGetCurrent()
        let wrappedCallback = { (result: Result<Set<Row>, RelationError>) -> Void in
            CFRunLoopPerformBlock(runloop, kCFRunLoopCommonModes, {
                callback(result)
            })
            CFRunLoopWakeUp(runloop)
        }
        
        super.registerQuery(relation, callback: wrappedCallback)
        
        if executionTimer == nil {
            executionTimer = CFRunLoopTimerCreateWithHandler(nil, 0, 0, 0, 0, { _ in
                self.execute()
            })
            CFRunLoopAddTimer(runloop, executionTimer, kCFRunLoopCommonModes)
        }
    }
    
    public override func execute() {
        CFRunLoopTimerInvalidate(executionTimer)
        executionTimer = nil
        
        super.execute()
    }
}
