//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import PLRelational

private typealias Spec = PlistDatabase.RelationSpec

enum Item {
    static let id = Attribute("item_id")
    static let text = Attribute("text")
    static let created = Attribute("created")
    static let completed = Attribute("completed")
    fileprivate static var spec: Spec { return .file(name: "item", path: "items.plist", scheme: [id, text, created, completed], primaryKeys: [id]) }
}

enum Tag {
    static let id = Attribute("tag_id")
    static let name = Attribute("name")
    fileprivate static var spec: Spec { return .file(name: "tag", path: "tags.plist", scheme: [id, name], primaryKeys: [id]) }
}

enum ItemTag {
    static let itemID = Item.id
    static let tagID = Tag.id
    fileprivate static var spec: Spec { return .file(name: "item_tag", path: "item_tags.plist", scheme: [itemID, tagID], primaryKeys: [itemID, tagID]) }
}

enum SelectedItem {
    static let id = Item.id
    fileprivate static var spec: Spec { return .transient(name: "selected_item", scheme: [id], primaryKeys: [id]) }
}
    
class Model {
    
    private let items: TransactionalRelation
    private let tags: TransactionalRelation
    private let itemTags: TransactionalRelation
    private let selectedItems: TransactionalRelation

    private let db: TransactionalDatabase

    init() {
        let specs: [Spec] = [
            Item.spec,
            Tag.spec,
            ItemTag.spec,
            SelectedItem.spec
        ]

        // Create a new database or open an existing one (stored on disk using plists)
        // TODO: Open existing if present
        let tmp = "/tmp" as NSString
        let dbname = "TodoApp.db"
        let path = tmp.appendingPathComponent(dbname)
        _ = try? FileManager.default.removeItem(atPath: path)
        let plistDB = PlistDatabase.create(URL(fileURLWithPath: path), specs).ok!

        // Wrap it in a TransactionalDatabase so that we can use snapshots
        let db = TransactionalDatabase(plistDB)

        // Make references to our source relations
        func relation(for spec: Spec) -> TransactionalRelation {
            return db[spec.name]
        }
        items = relation(for: Item.spec)
        tags = relation(for: Tag.spec)
        itemTags = relation(for: ItemTag.spec)
        selectedItems = relation(for: SelectedItem.spec)
        
        self.db = db
    }
}
