//
//  PropertiesModel.swift
//  Relational
//
//  Created by Chris Campbell on 5/30/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Foundation
import libRelational
import Binding

class PropertiesModel {
    
    let db: UndoableDatabase
    let selectedItems: Relation
    let textObjects: Relation

    /// - Parameters:
    ///     - db: The database.
    ///     - selectedItems: Relation with scheme [id, type, name].
    ///     - textObjects: Relation with scheme [id, editable, hint, font].
    init(db: UndoableDatabase, selectedItems: Relation, textObjects: Relation) {
        self.db = db
        self.selectedItems = selectedItems
        self.textObjects = textObjects
    }

    private lazy var selectedItemNamesRelation: Relation = { [unowned self] in
        return self.selectedItems.project(["name"])
    }()
    
    private lazy var selectedItemTypesRelation: Relation = { [unowned self] in
        return self.selectedItems.project(["type"])
    }()
    
    lazy var itemSelected: ValueBinding<Bool> = { [unowned self] in
        return self.selectedItems.nonEmpty
    }()
    
    lazy var itemNotSelected: ValueBinding<Bool> = { [unowned self] in
        return self.selectedItems.empty
    }()
    
    private lazy var selectedItemTypes: ValueBinding<Set<ItemType>> = { [unowned self] in
        return self.selectedItemTypesRelation.bindAllValues{ ItemType($0)! }
    }()
    
    lazy var selectedItemTypesString: ValueBinding<String> = { [unowned self] in
        // TODO: Is there a more efficient way to do this?
        let selectedItemCountBinding = self.selectedItems.count().bind{ $0.oneInteger }
        return selectedItemCountBinding.zip(self.selectedItemTypes).map { (count, types) in
            if types.count == 0 {
                return ""
            } else if count == 1 {
                return types.first!.name
            } else {
                if types.count == 1 {
                    return "Multiple \(types.first!.name)s"
                } else {
                    return "Multiple Items"
                }
            }
        }
    }()

    lazy var selectedItemNames: BidiValueBinding<String> = { [unowned self] in
        // TODO: s/Item/type.name/
        let relation = self.selectedItemNamesRelation
        return self.db.bidiBinding(
            relation,
            action: "Rename Item",
            get: { $0.oneString },
            set: { relation.updateString($0) }
        )
    }()
    
    lazy var selectedItemNamesPlaceholder: ValueBinding<String> = { [unowned self] in
        return self.selectedItemNamesRelation.stringWhenMulti("Multiple Values")
    }()
    
    private lazy var selectedTextObjects: Relation = { [unowned self] in
        return self.selectedItems
            .unique("type", matching: RelationValue(ItemType.Text.rawValue))
            .equijoin(self.textObjects, matching: ["id": "id"])
    }()
    
    lazy var textObjectProperties: ValueBinding<TextObjectPropertiesModel?> = { [unowned self] in
        return self.selectedTextObjects.whenNonEmpty{
            TextObjectPropertiesModel(db: self.db, selectedTextObjects: $0)
        }
    }()
}
