//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import PLRelational

enum DocDatabaseError: Error, CustomStringConvertible { case
    createFailed(underlying: RelationError),
    openFailed(underlying: RelationError),
    saveFailed(underlying: RelationError),
    replaceFailed(underlying: NSError)
    
    var description: String {
        return "DocDatabaseError(\(reason))"
    }
    
    var reason: String {
        switch self {
        case let .createFailed(e):
            return "Creation failed: \(e)"
        case let .openFailed(e):
            return "Open failed: \(e)"
        case let .saveFailed(e):
            return "Save failed: \(e)"
        case let .replaceFailed(e):
            return "Failed to replace file: \(e)"
        }
    }
}
