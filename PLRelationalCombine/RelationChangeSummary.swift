//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import PLRelational

/// TODO: Docs
public struct RelationChangeSummary<T> {
    public let added: [T]
    public let updated: [T]
    public let deleted: [T]
    
    public var isEmpty: Bool {
        return added.isEmpty && updated.isEmpty && deleted.isEmpty
    }
}

extension NegativeSet where T == Row {

    func summary<V>(idAttr: Attribute, _ mapFunc: (Row) -> V) -> RelationChangeSummary<V> {
        // First gather the rows that are being deleted (or updated)
        var deletedRows = Set(self.removed)

        var addedItems: [V] = []
        var updatedItems: [V] = []
        for row in self.added {
            let id = row[idAttr]
            if let index = deletedRows.firstIndex(where: { $0[idAttr] == id }) {
                // A row with this identifier appears in both sets, so it must've been updated; the added set
                // will contain the new row contents
                updatedItems.append(mapFunc(row))
                
                // We can be sure this item isn't being removed, so remove it from the set of deleted items
                deletedRows.remove(at: index)
            } else {
                // This is a newly added row
                addedItems.append(mapFunc(row))
            }
        }
        
        let deletedItems: [V] = Array(deletedRows.map(mapFunc))
        
        return RelationChangeSummary(added: addedItems, updated: updatedItems, deleted: deletedItems)
    }
}
