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
    /// - parameter update: Called for each deleted row to get updates. Must return an array of
    ///                     CascadingUpdate instances indicating what updates to apply on the basis of
    ///                     the deleted row.
    /// - parameter completionCallback: Called when the cascading delete completes.
    public func cascadingDelete(
        _ query: SelectExpression,
        cascade: @escaping (MutableRelation, Row) -> [(MutableRelation, SelectExpression)],
        update: @escaping (MutableRelation, Row) -> [CascadingUpdate] = { _ in [] },
        completionCallback: @escaping (Result<Void, RelationError>) -> Void) {
        let deleter = CascadingDeleter(initialRelation: self, initialQuery: query, cascade: cascade, update: update, completionCallback: completionCallback)
        deleter.run()
    }
    
    /// Do a tree deletion in the relation. This will delete all rows matching the query, as well as all rows whose
    /// childAttribute matches the value in the parentAttribute of a deleted row. This proceeds recursively until
    /// the whole tree is deleted, or an error occurs.
    public func treeDelete(
        _ query: SelectExpression,
        parentAttribute: Attribute,
        childAttribute: Attribute,
        update: @escaping (MutableRelation, Row) -> [CascadingUpdate] = { _ in [] },
        completionCallback: @escaping (Result<Void, RelationError>) -> Void) {
        let cascade = { (relation: MutableRelation, row: Row) -> [(MutableRelation, SelectExpression)] in
            let cascadingValue = row[parentAttribute]
            let cascadingQuery = childAttribute *== cascadingValue
            return [(self, cascadingQuery)]
        }
        cascadingDelete(query, cascade: cascade, update: update, completionCallback: completionCallback)
    }
}

public struct CascadingUpdate {
    /// The Relation to update.
    public var relation: Relation
    
    /// The query to filter what rows get updated.
    public var query: SelectExpression
    
    /// The attributes to copy from the target relation.
    public var attributes: [Attribute]
    
    /// The Relation from which to get the updated values. If this Relation doesn't contain
    /// exactly one value, the update is ignored.
    public var fromRelation: Relation
    
    public init(relation: Relation, query: SelectExpression, attributes: [Attribute], fromRelation: Relation) {
        self.relation = relation
        self.query = query
        self.attributes = attributes
        self.fromRelation = fromRelation
    }
}

/// This class implements the logic for cascadingDelete above. It got too hairy to express as a closure.
fileprivate class CascadingDeleter {
    /// The keys are actually MutableRelations but we're not allowed to say so.
    var pendingDeletes: ObjectDictionary<AnyObject, [SelectExpression]>
    
    let cascade: (MutableRelation, Row) -> [(MutableRelation, SelectExpression)]
    let update: (MutableRelation, Row) -> [CascadingUpdate]
    let completionCallback: (Result<Void, RelationError>) -> Void
    var error: RelationError? = nil
    
    init(initialRelation: MutableRelation, initialQuery: SelectExpression, cascade: @escaping (MutableRelation, Row) -> [(MutableRelation, SelectExpression)], update: @escaping (MutableRelation, Row) -> [CascadingUpdate], completionCallback: @escaping (Result<Void, RelationError>) -> Void) {
        self.pendingDeletes = [initialRelation: [initialQuery]]
        self.cascade = cascade
        self.update = update
        self.completionCallback = completionCallback
    }
    
    func run() {
        let runloop = CFRunLoopGetCurrent()!
        let updateManager = UpdateManager.currentInstance
        let group = DispatchGroup()
        
        let currentPendingDeletes = pendingDeletes
        pendingDeletes = [:]
        
        var pendingUpdates: [CascadingUpdate] = []
        
        for (relationObj, queries) in currentPendingDeletes {
            let relation = relationObj as! MutableRelation
            
            let query = queries.combined(with: *||)!
            
            group.enter()
            updateManager.registerQuery(
                relation.select(query),
                callback: runloop.wrap({ result in
                    switch result {
                    case .Ok(let rows) where !rows.isEmpty:
                        for row in rows {
                            let cascades = self.cascade(relation, row)
                            for (cascadeRelation, cascadeQuery) in cascades {
                                if self.pendingDeletes[cascadeRelation] == nil {
                                    self.pendingDeletes[cascadeRelation] = [cascadeQuery]
                                } else {
                                    self.pendingDeletes[cascadeRelation]!.append(cascadeQuery)
                                }
                            }
                            let updates = self.update(relation, row)
                            pendingUpdates.append(contentsOf: updates)
                        }
                        
                    case .Ok: // When rows are empty
                        relation.asyncDelete(query)
                        group.leave()
                    case .Err(let err):
                        self.error = err
                        group.leave()
                        
                    }
                }))
        }
        
        group.notify(queue: DispatchQueue.global(), execute: {
            runloop.async({
                for update in pendingUpdates {
                    group.enter()
                    var allRows: Set<Row> = []
                    updateManager.registerQuery(
                        update.fromRelation,
                        callback: runloop.wrap({ result in
                            switch result {
                            case .Ok(let rows) where !rows.isEmpty:
                                allRows.formUnion(rows)
                            case .Ok: // When rows are empty
                                // Update if we got exactly one row.
                                if let row = allRows.first, allRows.count == 1 {
                                    let newValues = row.rowWithAttributes(update.attributes)
                                    update.relation.asyncUpdate(update.query, newValues: newValues)
                                }
                                group.leave()
                            case .Err(let err):
                                self.error = err
                                group.leave()
                            }
                        }))
                }
                
                group.notify(queue: DispatchQueue.global(), execute: {
                    runloop.async({
                        if let error = self.error {
                            self.completionCallback(.Err(error))
                        } else if self.pendingDeletes.isEmpty {
                            self.completionCallback(.Ok())
                        } else {
                            self.run()
                        }
                    })
                })
            })
        })
    }
}
