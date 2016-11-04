//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import PLRelational
import Binding
import BindableControls

class ImageObjectPropertiesModel {
    
    let db: UndoableDatabase
    let selectedImageObjects: Relation
    
    /// - Parameters:
    ///     - db: The database.
    ///     - selectedImageObjects: Relation with scheme [id, editable].
    init(db: UndoableDatabase, selectedImageObjects: Relation) {
        self.db = db
        self.selectedImageObjects = selectedImageObjects
    }
    
    private lazy var editableRelation: Relation = { [unowned self] in
        return self.selectedImageObjects.project(["editable"])
    }()
    
    lazy var editable: ReadWriteProperty<CheckState> = { [unowned self] in
        return self.db.bidiProperty(
            self.editableRelation,
            action: "Change Editable",
            get: { CheckState($0.oneBoolOrNil) },
            set: { self.editableRelation.updateBoolean($0.boolValue) }
        )
    }()
}
