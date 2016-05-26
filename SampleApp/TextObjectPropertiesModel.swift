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
    
    let selectedTextObjects: Relation
    
    init(selectedTextObjects: Relation) {
        self.selectedTextObjects = selectedTextObjects
    }

    private lazy var editableRelation: Relation = { [unowned self] in
        return self.selectedTextObjects.project(["editable"])
    }()

    private lazy var hintRelation: Relation = { [unowned self] in
        return self.selectedTextObjects.project(["hint"])
    }()

    // TODO: Bidi
    lazy var editable: ValueBinding<Bool?> = { [unowned self] in
        return self.editableRelation.oneBoolOrNil
    }()
    
    // TODO: Bidi
    lazy var hint: ValueBinding<String> = { [unowned self] in
        return self.hintRelation.oneString
    }()
    
    lazy var hintPlaceholder: ValueBinding<String> = { [unowned self] in
        return self.hintRelation.stringWhenMulti("Multiple Values")
    }()
}
