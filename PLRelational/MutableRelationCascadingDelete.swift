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
    /// - parameter affectedRelations: An array of all relations that this operation will affect.
    ///                                This array must include all relations that will be updated
    ///                                or deleted, otherwise notifications won't work right. It is
    ///                                acceptable to pass in more than will actually be changed.
    ///                                This will generate spurious but harmless change notifications.
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
        affectedRelations: [MutableRelation],
        cascade: @escaping (MutableRelation, Row) -> [(MutableRelation, SelectExpression)],
        update: @escaping (MutableRelation, Row) -> [CascadingUpdate] = { _ in [] },
        completionCallback: @escaping (Result<Void, RelationError>) -> Void) {
        
        let context = AsyncManager.currentInstance.runloopDispatchContext()
        func callCompletion(_ result: Result<Void, RelationError>) {
            context.async({
                completionCallback(result)
            })
        }
        
        AsyncManager.currentInstance.registerCustomAction(affectedRelations: affectedRelations, {
            // The keys are actually MutableRelations but we're not allowed to say so.
            var pendingDeletes: ObjectDictionary<AnyObject, [SelectExpression]> = [self: [query]]
            
            while !pendingDeletes.isEmpty {
                let currentPendingDeletes = pendingDeletes
                pendingDeletes = [:]
                
                var pendingUpdates: [CascadingUpdate] = []
                
                for (relationObj, queries) in currentPendingDeletes {
                    let relation = relationObj as! MutableRelation
                    
                    let query = queries.combined(with: *||)!
                    for row in relation.select(query).rows() {
                        switch row {
                        case .Ok(let row):
                            let cascades = cascade(relation, row)
                            for (cascadeRelation, cascadeQuery) in cascades {
                                if pendingDeletes[cascadeRelation] == nil {
                                    pendingDeletes[cascadeRelation] = [cascadeQuery]
                                } else {
                                    pendingDeletes[cascadeRelation]!.append(cascadeQuery)
                                }
                            }
                            let updates = update(relation, row)
                            pendingUpdates.append(contentsOf: updates)
                        case .Err(let err):
                            callCompletion(.Err(err))
                            return err
                        }
                    }
                    let result = relation.delete(query)
                    if let err = result.err {
                        callCompletion(.Err(err))
                        return err
                    }
                }
                
                for update in pendingUpdates {
                    let rows = Array(update.fromRelation.rows().prefix(2))
                    if !rows.isEmpty {
                        if let err = rows.first?.err ?? rows.last?.err {
                            callCompletion(.Err(err))
                            return err
                        } else if let row = rows
                            .first?.ok, rows.count == 1 {
                            // Update if we got exactly one row.
                            let newValues = row.rowWithAttributes(update.attributes)
                            
                            // Work around `mutating` update
                            var relation = update.relation
                            precondition(asObject(relation) != nil, "Cannot update non-object Relation.")
                            let result = relation.update(update.query, newValues: newValues)
                            if let err = result.err {
                                callCompletion(.Err(err))
                                return err
                            }
                        }
                    }
                }
            }
            callCompletion(.Ok())
            return nil
        })
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
        cascadingDelete(query, affectedRelations: [self], cascade: cascade, update: update, completionCallback: completionCallback)
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
