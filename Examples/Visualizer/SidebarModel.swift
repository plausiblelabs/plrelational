//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import PLRelational
import PLRelationalBinding

class SidebarModel {
    
    let db: DocDatabase
    private let selectedObjects: Relation
    
    /// - Parameters:
    ///     - db: The database.
    ///     - selectedObjects: Relation with scheme [id, type, name].
    init(db: DocDatabase, selectedObjects: Relation) {
        precondition(selectedObjects.scheme == DB.Object.scheme)
        
        self.db = db
        self.selectedObjects = selectedObjects
    }
    
    lazy var itemNotSelected: AsyncReadableProperty<Bool> = {
        return self.selectedObjects.empty.property()
    }()
}
