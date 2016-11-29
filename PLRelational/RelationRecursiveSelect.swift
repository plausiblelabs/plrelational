//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

extension Relation {
    /// Perform a recursive `select` query on this relation.  This is modeled after `cascadingDelete`.
    public func recursiveSelect<T>(
        initialQueryAttr: Attribute,
        initialQueryValue: RelationValue,
        initialValue: T,
        rowCallback: @escaping (Relation & AnyObject, Row, T) -> Result<(T, [RecursiveQuery]), RelationError>,
        filterCallback: @escaping (T, [RecursiveQuery]) -> [RecursiveQuery],
        completionCallback: @escaping (Result<T, RelationError>) -> Void)
    {
        let initialQuery = RecursiveQuery(relation: self, attr: initialQueryAttr, value: initialQueryValue)
        let op = RecursiveSelectOp(
            initialQuery: initialQuery,
            initialValue: initialValue,
            rowCallback: rowCallback,
            filterCallback: filterCallback,
            completionCallback: completionCallback)
        op.run()
    }
}

public struct RecursiveQuery {
    /// The relation to query.
    public let relation: Relation
    
    /// The attribute part of the select expression.
    public let attr: Attribute
    
    /// The value part of the select expression.
    public let value: RelationValue
    
    public init(relation: Relation, attr: Attribute, value: RelationValue) {
        self.relation = relation
        self.attr = attr
        self.value = value
    }
}

private class RecursiveSelectOp<T> {
    
    private let rowCallback: (Relation & AnyObject, Row, T) -> Result<(T, [RecursiveQuery]), RelationError>
    private let filterCallback: (T, [RecursiveQuery]) -> [RecursiveQuery]
    private let completionCallback: (Result<T, RelationError>) -> Void
    
    /// The keys are actually Relations but we're not allowed to say so.
    private var pendingQueries: ObjectDictionary<AnyObject, [RecursiveQuery]>
    private var accum: T
    private var error: RelationError? = nil
    
    init(initialQuery: RecursiveQuery,
         initialValue: T,
         rowCallback: @escaping (Relation & AnyObject, Row, T) -> Result<(T, [RecursiveQuery]), RelationError>,
         filterCallback: @escaping (T, [RecursiveQuery]) -> [RecursiveQuery],
         completionCallback: @escaping (Result<T, RelationError>) -> Void)
    {
        self.pendingQueries = [initialQuery.relation as AnyObject: [initialQuery]]
        self.accum = initialValue
        self.rowCallback = rowCallback
        self.filterCallback = filterCallback
        self.completionCallback = completionCallback
    }
    
    func run() {
        let runloop = CFRunLoopGetCurrent()!
        let asyncManager = AsyncManager.currentInstance
        let group = DispatchGroup()
        
        let currentPendingQueries = pendingQueries
        pendingQueries = [:]

        for (relationObj, queries) in currentPendingQueries {
            let relation = relationObj as! MutableRelation

            // Only include identifiers for which we don't already have a stored value
            // TODO: Apply filter so that we don't make redundant queries
            let query = queries
                .map{ $0.attr *== $0.value }
                .combined(with: *||)!
        
            group.enter()
            asyncManager.registerQuery(
                relation.select(query),
                callback: runloop.wrap({ result in
                    switch result {
                    case .Ok(let rows) where !rows.isEmpty:
                        for row in rows {
                            // TODO: Handle error
                            let rowCallbackResult = self.rowCallback(relation, row, self.accum).ok!
                            self.accum = rowCallbackResult.0
                            for query in rowCallbackResult.1 {
                                let queryRelation = query.relation as AnyObject
                                if self.pendingQueries[queryRelation] == nil {
                                    self.pendingQueries[queryRelation] = [query]
                                } else {
                                    self.pendingQueries[queryRelation]!.append(query)
                                }
                            }
                        }
                    case .Ok: // When rows are empty
                        group.leave()
                    case .Err(let err):
                        self.error = err
                        group.leave()
                    }
                })
            )
        }
        
        group.notify(queue: DispatchQueue.global(), execute: {
            runloop.async({
                if let error = self.error {
                    self.completionCallback(.Err(error))
                } else if self.pendingQueries.isEmpty {
                    self.completionCallback(.Ok(self.accum))
                } else {
                    self.run()
                }
            })
        })
    }
}
