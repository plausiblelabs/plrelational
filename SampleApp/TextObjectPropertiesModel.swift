//
//  TextObjectPropsModel.swift
//  Relational
//
//  Created by Chris Campbell on 5/25/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Foundation
import libRelational

class TextObjectPropertiesModel {
    
    let db: UndoableDatabase
    let selectedTextObjects: Relation
    
    init(db: UndoableDatabase, selectedTextObjects: Relation) {
        self.db = db
        self.selectedTextObjects = selectedTextObjects
    }

    private lazy var editableRelation: Relation = { [unowned self] in
        return self.selectedTextObjects.project(["editable"])
    }()

    private lazy var hintRelation: Relation = { [unowned self] in
        return self.selectedTextObjects.project(["hint"])
    }()

    lazy var editable: BidiValueBinding<Checkbox.CheckState> = { [unowned self] in
        return self.db.bidiBinding(
            self.editableRelation,
            action: "Change Editable",
            get: { Checkbox.CheckState($0.oneBool) },
            set: { self.editableRelation.updateBoolean($0.boolValue) }
        )
    }()
    
    lazy var hint: BidiValueBinding<String> = { [unowned self] in
        return self.db.bidiBinding(
            self.hintRelation,
            action: "Change Hint",
            get: { $0.oneString },
            set: { self.hintRelation.updateString($0) }
        )
    }()
    
    lazy var hintPlaceholder: ValueBinding<String> = { [unowned self] in
        return self.hintRelation.stringWhenMulti("Multiple Values")
    }()
}
