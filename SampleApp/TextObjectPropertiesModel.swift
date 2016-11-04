//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import PLRelational
import PLRelationalBinding
import BindableControls

class TextObjectPropertiesModel {
    
    let db: UndoableDatabase
    let selectedTextObjects: Relation
    
    /// - Parameters:
    ///     - db: The database.
    ///     - selectedTextObjects: Relation with scheme [id, editable, hint, font].
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

    private lazy var fontRelation: Relation = { [unowned self] in
        return self.selectedTextObjects.project(["font"])
    }()

    lazy var editable: ReadWriteProperty<CheckState> = { [unowned self] in
        return self.db.bidiProperty(
            self.editableRelation,
            action: "Change Editable",
            get: { CheckState($0.oneBoolOrNil) },
            set: { self.editableRelation.updateBoolean($0.boolValue) }
        )
    }()
    
    lazy var hint: ReadWriteProperty<String> = { [unowned self] in
        return self.db.bidiProperty(
            self.hintRelation,
            action: "Change Hint",
            get: { $0.oneString },
            set: { self.hintRelation.updateString($0) }
        )
    }()
    
    lazy var hintPlaceholder: ReadableProperty<String> = { [unowned self] in
        return self.hintRelation.stringWhenMulti("Multiple Values")
    }()
    
    var availableFonts: [String] = ["Futura", "Helvetica", "Monaco"]
    
    lazy var font: ReadWriteProperty<String?> = { [unowned self] in
        return self.db.bidiProperty(
            self.fontRelation,
            action: "Change Font",
            get: { $0.oneStringOrNil },
            set: { self.fontRelation.updateNullableString($0) }
        )
    }()
    
    lazy var fontPlaceholder: ReadableProperty<String> = { [unowned self] in
        return self.fontRelation.stringWhenMulti("Multiple", otherwise: "Default")
    }()
}
