//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import libRelational

enum ItemType: Int64 { case
    section = 0,
    group = 1,
    storedRelation = 2,
    sharedRelation = 3,
    privateRelation = 4
    
    init?(_ value: RelationValue) {
        self.init(rawValue: value.get()!)!
    }
    
    init?(_ row: Row) {
        self.init(row["type"])
    }
    
    var name: String {
        switch self {
        case .section: return "Section"
        case .group: return "Group"
        case .storedRelation: return "Stored Relation"
        case .sharedRelation: return "Shared Relation"
        case .privateRelation: return "Private Relation"
        }
    }
    
    var isGroupType: Bool {
        switch self {
        case .section, .group:
            return true
        default:
            return false
        }
    }
    
    var isObjectType: Bool {
        return !isGroupType
    }
}
