//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import PLRelational
import PLRelationalBinding
import PLBindableControls

private typealias Spec = PlistDatabase.RelationSpec

enum Item {
    static let id = Attribute("item_id")
    static let text = Attribute("text")
    static let created = Attribute("created")
    static let status = Attribute("status")
    fileprivate static var spec: Spec { return .file(name: "item", path: "items.plist", scheme: [id, text, created, status], primaryKeys: [id]) }
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
    
    let items: TransactionalRelation
    let tags: TransactionalRelation
    let itemTags: TransactionalRelation
    let selectedItemIDs: TransactionalRelation

    private let db: TransactionalDatabase
    private let undoableDB: UndoableDatabase

    init(undoManager: PLBindableControls.UndoManager) {
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
        
        // Wrap that in an UndoableDatabase for easy undo/redo support
        let undoableDB = UndoableDatabase(db: db, undoManager: undoManager)

        // Make references to our source relations
        func relation(for spec: Spec) -> TransactionalRelation {
            return db[spec.name]
        }
        items = relation(for: Item.spec)
        tags = relation(for: Tag.spec)
        itemTags = relation(for: ItemTag.spec)
        selectedItemIDs = relation(for: SelectedItem.spec)
        
        self.db = db
        self.undoableDB = undoableDB
        
        // XXX: Temporarily add some initial data for testing purposes
        addItem("One")
        addItem("Two")
        addItem("Three")
    }
    
    func undoableBidiProperty<T>(action: String, signal: Signal<T>, update: @escaping (T) -> Void) -> AsyncReadWriteProperty<T> {
        return undoableDB.bidiProperty(action: action, signal: signal, update: update)
    }
    
    private func addItem(_ text: String) {
        // Use UUIDs to uniquely identify rows
        let id = RelationValue(uuidString())

        // Use a string representation of the current time to make our life easier
        let now = timestampString()
        let created = RelationValue(now)
        
        // Here we cheat a little.  Because ArrayProperty currently only knows how to
        // sort on a single attribute (temporary limitation), we cram two things --
        // completed flag and the timestamp of the action -- into a single string of
        // the form "<0/1> <timestamp>".  This allows us to keep to-do items sorted
        // in the list with pending items at top and completed items at bottom, with
        // pending items sorted with most recently added items at top, and completed
        // items sorted with most recently completed items at top.
        let status = RelationValue(statusString(completed: false, timestamp: now))
        
        items.asyncAdd([
            Item.id: id,
            Item.text: RelationValue(text),
            Item.created: created,
            Item.status: status
        ])
    }
    
    // MARK: - Properties

    /// Resolves to the item that is selected in the list of to-do items.
    lazy var selectedItems: Relation = {
        return self.selectedItemIDs.join(self.items)
    }()
    
    /// Resolves to `true` when an item is selected in the list of to-do items.
    lazy var hasSelection: AsyncReadableProperty<Bool> = {
        return self.selectedItems.nonEmpty.property()
    }()

    /// Returns a property that reflects the item text.
    func itemText(_ relation: Relation, initialValue: String?) -> AsyncReadWriteProperty<String> {
        return self.undoableBidiProperty(
            action: "Change Item Text",
            signal: relation.oneString(initialValue: initialValue),
            update: {
                relation.asyncUpdateString($0)
            }
        )
    }
}

private func uuidString() -> String {
    return UUID().uuidString
}

private let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f
}()

private func timestampString() -> String {
    return dateFormatter.string(from: Date())
}

private func statusString(completed: Bool, timestamp: String) -> String {
    return "\(completed ? 1 : 0) \(timestamp)"
}
