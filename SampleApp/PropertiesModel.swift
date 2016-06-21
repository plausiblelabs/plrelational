//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import libRelational
import Binding

class PropertiesModel {
    
    let db: UndoableDatabase
    let selectedItems: Relation
    let textObjects: Relation
    let imageObjects: Relation

    /// - Parameters:
    ///     - db: The database.
    ///     - selectedItems: Relation with scheme [id, type, name].
    ///     - textObjects: Relation with scheme [id, editable, hint, font].
    ///     - imageObjects: Relation with scheme [id, editable].
    init(db: UndoableDatabase, selectedItems: Relation, textObjects: Relation, imageObjects: Relation) {
        self.db = db
        self.selectedItems = selectedItems
        self.textObjects = textObjects
        self.imageObjects = imageObjects
    }

    private lazy var selectedItemNamesRelation: Relation = { [unowned self] in
        return self.selectedItems.project(["name"])
    }()
    
    private lazy var selectedItemTypesRelation: Relation = { [unowned self] in
        return self.selectedItems.project(["type"])
    }()
    
    lazy var itemSelected: ObservableValue<Bool> = { [unowned self] in
        return self.selectedItems.nonEmpty
    }()
    
    lazy var itemNotSelected: ObservableValue<Bool> = { [unowned self] in
        return self.selectedItems.empty
    }()
    
    private lazy var selectedItemTypes: ObservableValue<Set<ItemType>> = { [unowned self] in
        return self.selectedItemTypesRelation.observableAllValues{ ItemType($0)! }
    }()
    
    lazy var selectedItemTypesString: ObservableValue<String> = { [unowned self] in
        // TODO: Is there a more efficient way to do this?
        let selectedItemCountBinding = self.selectedItems.count().observable{ $0.oneInteger }
        return zip(selectedItemCountBinding, self.selectedItemTypes).map { (count, types) in
            if count == 1 && types.count == 1 {
                return types.first!.name
            } else if count > 1 {
                if types.count == 1 {
                    return "Multiple \(types.first!.name)s"
                } else {
                    return "Multiple Items"
                }
            } else {
                return ""
            }
        }
    }()

    lazy var selectedItemNames: BidiProperty<String> = { [unowned self] in
        // TODO: s/Item/type.name/
        let relation = self.selectedItemNamesRelation
        return self.db.bidiProperty(
            relation,
            action: "Rename Item",
            get: { $0.oneString },
            set: { relation.updateString($0) }
        )
    }()
    
    lazy var selectedItemNamesPlaceholder: ObservableValue<String> = { [unowned self] in
        return self.selectedItemNamesRelation.stringWhenMulti("Multiple Values")
    }()
    
    private func selectedObjects(type: ItemType, _ relation: Relation) -> Relation {
        return self.selectedItems
            .unique("type", matching: RelationValue(type.rawValue))
            .equijoin(relation, matching: ["id": "id"])
    }
    
    lazy var textObjectProperties: ObservableValue<TextObjectPropertiesModel?> = { [unowned self] in
        return self.selectedObjects(.Text, self.textObjects).whenNonEmpty{
            TextObjectPropertiesModel(db: self.db, selectedTextObjects: $0)
        }
    }()
    
    lazy var imageObjectProperties: ObservableValue<ImageObjectPropertiesModel?> = { [unowned self] in
        return self.selectedObjects(.Image, self.imageObjects).whenNonEmpty{
            ImageObjectPropertiesModel(db: self.db, selectedImageObjects: $0)
        }
    }()
}
