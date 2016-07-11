//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import libRelational

// TODO: Use lazy sequences here
struct RelationChangeParts {
    let addedRows: [Row]
    let updatedRows: [Row]
    let deletedIDs: [RelationValue]
}

extension RelationChange {

    /// Extracts the added, updated, and removed rows from this RelationChange.
    func parts(idAttr: Attribute) -> RelationChangeParts {
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
        if let adds = self.added, removes = self.removed {
            let updated = removes.project([idAttr]).join(adds)
            updatedRows = updated.rows().flatMap{$0.ok}
        } else {
            updatedRows = []
        }

        let deletedIDs: [RelationValue]
        if let removes = self.removed {
            let removedIDs: Relation
            if let adds = self.added {
                removedIDs = removes.project([idAttr]).difference(adds.project([idAttr]))
            } else {
                removedIDs = removes.project([idAttr])
            }
            deletedIDs = removedIDs.rows().flatMap{$0.ok?[idAttr]}
        } else {
            deletedIDs = []
        }
        
        return RelationChangeParts(addedRows: addedRows, updatedRows: updatedRows, deletedIDs: deletedIDs)
    }
}