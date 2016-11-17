//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

extension Relation {
    /// Perform a recursive `select` query on this relation.  This is modeled after `cascadingDelete`.
    public func recursiveSelect<T>(
        idAttr: Attribute,
        initialID: RelationValue,
        rowCallback: @escaping (Row) -> Result<(T, [RelationValue]), RelationError>,
        completionCallback: @escaping (Result<[RelationValue: T], RelationError>) -> Void)
    {
        let op = RecursiveSelectOp(
            relation: self,
            idAttr: idAttr,
            initialID: initialID,
            rowCallback: rowCallback,
            completionCallback: completionCallback)
        op.run()
    }
}

private class RecursiveSelectOp<T> {
    
    private let relation: Relation
    private let idAttr: Attribute
    private let rowCallback: (Row) -> Result<(T, [RelationValue]), RelationError>
    private let completionCallback: (Result<[RelationValue: T], RelationError>) -> Void
    
    private var pendingIDs: Set<RelationValue>
    private var values: [RelationValue: T] = [:]
    private var error: RelationError? = nil
    
    init(relation: Relation,
         idAttr: Attribute,
         initialID: RelationValue,
         rowCallback: @escaping (Row) -> Result<(T, [RelationValue]), RelationError>,
         completionCallback: @escaping (Result<[RelationValue: T], RelationError>) -> Void)
    {
        self.relation = relation
        self.idAttr = idAttr
        self.pendingIDs = [initialID]
        self.rowCallback = rowCallback
        self.completionCallback = completionCallback
    }
    
    func run() {
        let runloop = CFRunLoopGetCurrent()!
        let asyncManager = AsyncManager.currentInstance
        let group = DispatchGroup()
        
        let currentPendingIDs = pendingIDs
        pendingIDs = []

        // Only include identifiers for which we don't already have a stored value
        let query = currentPendingIDs
            .filter{ !values.keys.contains($0) }
            .map{ idAttr *== $0 }
            .combined(with: *||)!
        
        group.enter()
        asyncManager.registerQuery(
            relation.select(query),
            callback: runloop.wrap({ result in
                switch result {
                case .Ok(let rows) where !rows.isEmpty:
                    for row in rows {
                        // TODO: Handle error
                        let rowResult = self.rowCallback(row).ok!
                        let rowID = row[self.idAttr]
                        let rowValue = rowResult.0
                        let rowPendingIDs = rowResult.1
                        self.values[rowID] = rowValue
                        self.pendingIDs.formUnion(rowPendingIDs)
                    }
                case .Ok: // When rows are empty
                    group.leave()
                case .Err(let err):
                    self.error = err
                    group.leave()
                }
            })
        )
        
        group.notify(queue: DispatchQueue.global(), execute: {
            runloop.async({
                if let error = self.error {
                    self.completionCallback(.Err(error))
                } else if self.pendingIDs.isEmpty {
                    self.completionCallback(.Ok(self.values))
                } else {
                    self.run()
                }
            })
        })
    }
}
