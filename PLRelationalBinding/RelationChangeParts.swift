//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import PLRelational

// TODO: Use lazy sequences here
public struct RelationChangeParts {
    public let addedRows: [Row]
    public let updatedRows: [Row]
    public let deletedRows: [Row]
    public let deletedIDs: [RelationValue]
    
    public init(addedRows: [Row], updatedRows: [Row], deletedRows: [Row], deletedIDs: [RelationValue]) {
        self.addedRows = addedRows
        self.updatedRows = updatedRows
        self.deletedRows = deletedRows
        self.deletedIDs = deletedIDs
    }
    
    public var isEmpty: Bool {
        return addedRows.isEmpty && updatedRows.isEmpty && deletedIDs.isEmpty
    }
}

extension RelationChange {

    /// Extracts the added, updated, and removed rows from this RelationChange.
    public func parts(_ idAttr: Attribute) -> RelationChangeParts {
        let addedRows: [Row]
        if let adds = self.added {
            let added: Relation
            if let removes = self.removed {
                added = adds.project([idAttr]).difference(removes.project([idAttr])).join(adds)
            } else {
                added = adds
            }
            // TODO: Error handling
            addedRows = added.rows().flatMap{$0.ok}
        } else {
            addedRows = []
        }
        
        let updatedRows: [Row]
        if let adds = self.added, let removes = self.removed {
            let updated = removes.project([idAttr]).join(adds)
            updatedRows = updated.rows().flatMap{$0.ok}
        } else {
            updatedRows = []
        }

        let deletedRows: [Row]
        let deletedIDs: [RelationValue]
        if let removes = self.removed {
            let removed: Relation
            if let adds = self.added {
                removed = removes.project([idAttr]).difference(adds.project([idAttr])).join(removes)
            } else {
                removed = removes
            }
            deletedRows = removed.rows().flatMap{$0.ok}
            deletedIDs = deletedRows.map{$0[idAttr]}
        } else {
            deletedRows = []
            deletedIDs = []
        }
        
        return RelationChangeParts(addedRows: addedRows, updatedRows: updatedRows, deletedRows: deletedRows, deletedIDs: deletedIDs)
    }
}

/// :nodoc:
/// Extracts the added, updated, and removed rows from the given NegativeSet.
public func partsOf(_ set: NegativeSet<Row>, idAttr: Attribute) -> RelationChangeParts {
    // First gather the rows that are being deleted (or updated)
    var deletedRows = Set(set.removed)

    var addedRows: [Row] = []
    var updatedRows: [Row] = []
    for row in set.added {
        let id = row[idAttr]
        if let index = deletedRows.index(where: { $0[idAttr] == id }) {
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
    
    let deletedIDs = deletedRows.map{ $0[idAttr] }
    return RelationChangeParts(addedRows: addedRows, updatedRows: updatedRows, deletedRows: Array(deletedRows), deletedIDs: deletedIDs)
}
