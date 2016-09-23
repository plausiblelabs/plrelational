//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation


extension MutableRelation {
    /// Perform a cascading delete on the relation. The `query` is used for the initial deletion run. For
    /// every deleted row, `cascade` is called to get further deletions to perform. When nothing remains
    /// to be deleted, `completionCallback` is called.
    ///
    /// - parameter query: The initial query for rows to delete on this relation.
    /// - parameter cascade: Called for each deleted row to get cascades. Must return an array of
    ///                      `(MutableRelation, SelectExpression)` pairs indicating what to delete next.
    ///                      The same relation can be specified to perform a cascading delete within the
    ///                      relation, or a different one can be specified to do cross-relation cascades.
    /// - parameter completionCallback: Called when the cascading delete completes.
    public func cascadingDelete(_ query: SelectExpression, cascade: @escaping (MutableRelation, Row) -> [(MutableRelation, SelectExpression)], completionCallback: @escaping (Result<Void, RelationError>) -> Void) {
        let deleter = CascadingDeleter(initialRelation: self, initialQuery: query, cascade: cascade, completionCallback: completionCallback)
        deleter.run()
    }
    
    /// Do a tree deletion in the relation. This will delete all rows matching the query, as well as all rows whose
    /// childAttribute matches the value in the parentAttribute of a deleted row. This proceeds recursively until
    /// the whole tree is deleted, or an error occurs.
    public func treeDelete(_ query: SelectExpression, parentAttribute: Attribute, childAttribute: Attribute, completionCallback: @escaping (Result<Void, RelationError>) -> Void) {
        let cascade = { (relation: MutableRelation, row: Row) -> [(MutableRelation, SelectExpression)] in
            let cascadingValue = row[parentAttribute]
            let cascadingQuery = childAttribute *== cascadingValue
            return [(self, cascadingQuery)]
        }
        cascadingDelete(query, cascade: cascade, completionCallback: completionCallback)
    }
}

/// This class implements the logic for cascadingDelete above. It got too hairy to express as a closure.
fileprivate class CascadingDeleter {
    /// The keys are actually MutableRelations but we're not allowed to say so.
    var pending: ObjectDictionary<AnyObject, [SelectExpression]>
    var cascade: (MutableRelation, Row) -> [(MutableRelation, SelectExpression)]
    var completionCallback: (Result<Void, RelationError>) -> Void
    var error: RelationError? = nil
    
    init(initialRelation: MutableRelation, initialQuery: SelectExpression, cascade: @escaping (MutableRelation, Row) -> [(MutableRelation, SelectExpression)], completionCallback: @escaping (Result<Void, RelationError>) -> Void) {
        self.pending = [initialRelation: [initialQuery]]
        self.cascade = cascade
        self.completionCallback = completionCallback
    }
    
    func run() {
        let group = DispatchGroup()
        
        let currentPending = pending
        pending = [:]
        for (relationObj, queries) in currentPending {
            let relation = relationObj as! MutableRelation
            
            // Build up a tree of ORs that combine the queries. We do this in a weird pairwise way
            // to keep the tree shallow.
            var expressions = queries
            while expressions.count > 1 {
                for i in 0 ..< expressions.count / 2 {
                    let lhs = expressions.remove(at: i)
                    let rhs = expressions.remove(at: i)
                    expressions.insert(lhs *|| rhs, at: i)
                }
            }
            let query = expressions[0]
            
            group.enter()
            relation.select(query).asyncBulkRows({ result in
                switch result {
                case .Ok(let rows) where !rows.isEmpty:
                    for row in rows {
                        let cascades = self.cascade(relation, row)
                        for (cascadeRelation, cascadeQuery) in cascades {
                            if self.pending[cascadeRelation] == nil {
                                self.pending[cascadeRelation] = [cascadeQuery]
                            } else {
                                self.pending[cascadeRelation]!.append(cascadeQuery)
                            }
                        }
                    }
                    
                case .Ok: // When rows are empty
                    relation.asyncDelete(query)
                    group.leave()
                case .Err(let err):
                    self.error = err
                    group.leave()

                }
            })
        }
        
        let runloop = CFRunLoopGetCurrent()!
        group.notify(queue: DispatchQueue.global(), execute: {
            runloop.async({
                if let error = self.error {
                    self.completionCallback(.Err(error))
                } else if self.pending.isEmpty {
                    self.completionCallback(.Ok())
                } else {
                    self.run()
                }
            })
        })
    }
}
