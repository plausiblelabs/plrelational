//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

extension Relation where Self: AnyObject {
    /// Perform a recursive `select` query on this relation.  This is modeled after `cascadingDelete`.
    public func recursiveSelect<T>(
        initialQueryAttr: Attribute,
        initialQueryValue: RelationValue,
        initialValue: T,
        rowCallback: @escaping (RelationObject, Row, T) -> Result<(T, [RecursiveQuery]), RelationError>,
        filterCallback: @escaping (T, Set<RecursiveQuery>) -> Set<RecursiveQuery>,
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

public struct RecursiveQuery: Hashable {
    /// The relation to query.
    public let relation: RelationObject
    
    /// The attribute part of the select expression.
    public let attr: Attribute
    
    /// The value part of the select expression.
    public let value: RelationValue
    
    public init(relation: RelationObject, attr: Attribute, value: RelationValue) {
        self.relation = relation
        self.attr = attr
        self.value = value
    }
    
    public var hashValue: Int {
        return attr.hashValue ^ value.hashValue
    }
}

public func ==(a: RecursiveQuery, b: RecursiveQuery) -> Bool {
    return a.relation === b.relation && a.attr == b.attr && a.value == b.value
}

private class RecursiveSelectOp<T> {
    
    private let rowCallback: (RelationObject, Row, T) -> Result<(T, [RecursiveQuery]), RelationError>
    private let filterCallback: (T, Set<RecursiveQuery>) -> Set<RecursiveQuery>
    private let completionCallback: (Result<T, RelationError>) -> Void
    
    /// The keys are actually Relations but we're not allowed to say so.
    private var pendingQueries: ObjectDictionary<AnyObject, Set<RecursiveQuery>>
    private var accum: T
    private var error: RelationError? = nil
    
    init(initialQuery: RecursiveQuery,
         initialValue: T,
         rowCallback: @escaping (RelationObject, Row, T) -> Result<(T, [RecursiveQuery]), RelationError>,
         filterCallback: @escaping (T, Set<RecursiveQuery>) -> Set<RecursiveQuery>,
         completionCallback: @escaping (Result<T, RelationError>) -> Void)
    {
        self.pendingQueries = [initialQuery.relation as AnyObject: [initialQuery]]
        self.accum = initialValue
        self.rowCallback = rowCallback
        self.filterCallback = filterCallback
        self.completionCallback = completionCallback
    }
    
    func run() {
        let context = AsyncManager.currentInstance.runloopDispatchContext()
        let asyncManager = AsyncManager.currentInstance
        let group = DispatchGroup()
        
        let currentPendingQueries = pendingQueries
        pendingQueries = [:]

        for (relationObj, queries) in currentPendingQueries {
            let relation = relationObj as! RelationObject

            // Apply filter so that we don't query redundantly (like if we already fetched and stored a value)
            let combinedQuery = self.filterCallback(self.accum, queries)
                .map{ $0.attr *== $0.value }
                .combined(with: *||)
            guard let query = combinedQuery else { continue }
        
            group.enter()
            asyncManager.registerQuery(
                relation.select(query),
                callback: context.wrap({ result in
                    switch result {
                    case .Ok(let rows) where !rows.isEmpty:
                        for row in rows {
                            // TODO: Handle error
                            let rowCallbackResult = self.rowCallback(relation, row, self.accum).ok!
                            self.accum = rowCallbackResult.0
                            for query in rowCallbackResult.1 {
                                let queryRelation = query.relation
                                if self.pendingQueries[queryRelation] == nil {
                                    self.pendingQueries[queryRelation] = [query]
                                } else {
                                    self.pendingQueries[queryRelation]!.insert(query)
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
            context.async({
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
