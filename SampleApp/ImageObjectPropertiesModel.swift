//
//  ImageObjectPropertiesModel.swift
//  Relational
//
//  Created by Chris Campbell on 6/7/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Foundation
import libRelational
import Binding

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
    
    lazy var editable: MutableObservableValue<Checkbox.CheckState> = { [unowned self] in
        return self.db.observe(
            self.editableRelation,
            action: "Change Editable",
            get: { Checkbox.CheckState($0.oneBoolOrNil) },
            set: { self.editableRelation.updateBoolean($0.boolValue) }
        )
    }()
}
