//
// Copyright (c) 2019 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import PLRelational

/// TODO: Docs
public struct RelationChangeSummary {
    public let added: [Row]
    public let updated: [Row]
    public let deleted: [Row]
    
    public var isEmpty: Bool {
        return added.isEmpty && updated.isEmpty && deleted.isEmpty
    }
}

extension NegativeSet where T == Row {

    func summary(idAttr: Attribute) -> RelationChangeSummary {
        // First gather the rows that are being deleted (or updated)
        var deletedRows = Set(self.removed)

        var addedRows: [Row] = []
        var updatedRows: [Row] = []
        for row in self.added {
            let id = row[idAttr]
            if let index = deletedRows.firstIndex(where: { $0[idAttr] == id }) {
                // A row with this identifier appears in both sets, so it must've been updated; the added set
                // will contain the new row contents
                updatedRows.append(row)
                
                // We can be sure this item isn't being removed, so remove it from the set of deleted items
                deletedRows.remove(at: index)
            } else {
                // This is a newly added row
                addedRows.append(row)
            }
        }
        
        return RelationChangeSummary(added: addedRows, updated: updatedRows, deleted: Array(deletedRows))
    }
}
