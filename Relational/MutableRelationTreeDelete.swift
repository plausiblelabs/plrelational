//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

extension MutableRelation where Self: AnyObject {
    /// Do a tree deletion in the relation. This will delete all rows matching the query, as well as all rows whose
    /// childAttribute matches the value in the parentAttribute of a deleted row. This proceeds recursively until
    /// the whole tree is deleted, or an error occurs.
    ///
    /// NOTE: because it's async, this only works on reference types, not value types.
    public func treeDelete(_ query: SelectExpression, parentAttribute: Attribute, childAttribute: Attribute, completionCallback: @escaping (Result<Void, RelationError>) -> Void) {
        let postprocessor = { (rows: Set<Row>) -> SelectExpression? in
            // If there are no matching rows, then we're done.
            if rows.isEmpty { return nil }
            
            // All of the attributes in the parents that were just deleted.
            let cascadingValues = Set(rows.map({ $0[parentAttribute] }))
            
            // Equality expressions that look for a child attribute equal to one of them.
            let equalityExpressions = cascadingValues.map({ childAttribute *== $0 })
            
            // Build up a tree of ORs that combine them all. We do this in a weird pairwise way
            // to keep the tree shallow.
            var expressions = equalityExpressions
            while expressions.count > 1 {
                for i in 0 ..< expressions.count / 2 {
                    let lhs = expressions.remove(at: i)
                    let rhs = expressions.remove(at: i)
                    expressions.insert(lhs *|| rhs, at: i)
                }
            }
            
            // Recursively delete using that query.
            return expressions[0]
        }
        
        let callback = { (result: Result<SelectExpression?, RelationError>) -> Void in
            switch result {
            case .Err(let err):
                completionCallback(.Err(err))
            case .Ok(nil):
                completionCallback(.Ok())
            case .Ok(let nextQuery?):
                self.asyncDelete(query)
                self.treeDelete(nextQuery, parentAttribute: parentAttribute, childAttribute: childAttribute, completionCallback: completionCallback)
            }
        }
        
        self.select(query).asyncAllRows(postprocessor: postprocessor, completion: callback)
    }
}
