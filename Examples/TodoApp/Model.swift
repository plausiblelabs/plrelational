//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import PLRelational
import PLRelationalBinding
import PLBindableControls

private typealias Spec = PlistDatabase.RelationSpec

/// Scheme for the `item` relation that holds the to-do items.
enum Item {
    enum id: TypedStringAttribute {
        static var attribute: Attribute = "item_id"
    }
    enum title: TypedStringAttribute {}
    enum created: TypedStringAttribute {}
    enum status: TypedStringAttribute {}
    enum notes: TypedStringAttribute {}
    fileprivate static var spec: Spec { return .file(
        name: "item",
        path: "items.plist",
        scheme: [id.attribute, title.attribute, created.attribute, status.attribute, notes.attribute],
        primaryKeys: [id.attribute]
    )}
}

/// Scheme for the `tag` relation that holds the named tags.
enum Tag {
    typealias Value = String
    
    enum id: TypedStringAttribute {
        static var attribute: Attribute = "tag_id"
    }
    enum name: TypedStringAttribute {}
    fileprivate static var spec: Spec { return .file(
        name: "tag",
        path: "tags.plist",
        scheme: [id.attribute, name.attribute],
        primaryKeys: [id.attribute]
    )}
}

/// Scheme for the `item_tag` relation that associates zero
/// or more tags with a to-do item.
enum ItemTag {
    typealias itemID = Item.id
    typealias tagID = Tag.id
    fileprivate static var spec: Spec { return .file(
        name: "item_tag",
        path: "item_tags.plist",
        scheme: [itemID.attribute, tagID.attribute],
        primaryKeys: [itemID.attribute, tagID.attribute]
    )}
}

/// Scheme for the `selected_item` relation that maintains
/// the selection state for the list of to-do items.
enum SelectedItem {
    typealias id = Item.id
    fileprivate static var spec: Spec { return .transient(
        name: "selected_item",
        scheme: [id.attribute],
        primaryKeys: [id.attribute]
    )}
}

class Model {
    
    let items: TransactionalRelation
    let tags: TransactionalRelation
    let itemTags: TransactionalRelation
    let selectedItemIDs: TransactionalRelation

    let allTags: AsyncReadableProperty<[RowArrayElement]>
    
    private let db: TransactionalDatabase
    let undoableDB: UndoableDatabase

    init(undoManager: PLRelationalBinding.UndoManager) {
        let specs: [Spec] = [
            Item.spec,
            Tag.spec,
            ItemTag.spec,
            SelectedItem.spec
        ]

        // Create a database or open an existing one (stored on disk using plists)
        let path = "/tmp/TodoApp.db"
        let dbExisted = FileManager.default.fileExists(atPath: path)
        let plistDB = PlistDatabase.create(URL(fileURLWithPath: path), specs).forcedOK

        // Wrap it in a TransactionalDatabase so that we can use snapshots, and
        // enable auto-save so that all changes are persisted to disk as needed
        let db = TransactionalDatabase(plistDB)
        db.saveOnTransactionEnd = true
        self.db = db

        // Wrap that in an UndoableDatabase for easy undo/redo support
        self.undoableDB = UndoableDatabase(db: db, undoManager: undoManager)

        // Make references to our source relations
        func relation(for spec: Spec) -> TransactionalRelation {
            return db[spec.name]
        }
        items = relation(for: Item.spec)
        tags = relation(for: Tag.spec)
        itemTags = relation(for: ItemTag.spec)
        selectedItemIDs = relation(for: SelectedItem.spec)
        
        // Keep the set of all tags cached for easy access
        self.allTags = tags
            .arrayProperty(idAttr: Tag.id.attribute, orderAttr: Tag.name.attribute)
            .fullArray()
        self.allTags.start()

        if !dbExisted {
            // Add a couple default tags
            addTag("home")
            addTag("work")
            addTag("urgent")
        }
    }

    /// MARK: - Items
    
    /// REQ-1
    /// Adds a new row to the `items` relation.
    private func addItem(_ title: String) {
        // Use UUIDs to uniquely identify rows.  Note that we can pass `id` directly
        // when initializing the row because `ItemID` conforms to the
        // `RelationValueConvertible` protocol.
        let id = ItemID()

        // Use a string representation of the current time to make our life easier
        let now = timestampString()
        
        // Here we cheat a little.  ArrayProperty currently only knows how to sort
        // on a single attribute (temporary limitation), we cram two things -- the
        // completed flag and the timestamp of the action -- into a single string of
        // the form "<0/1> <timestamp>".  This allows us to keep to-do items sorted
        // in the list with pending items at top and completed ones at bottom.
        let status = statusString(pending: true, timestamp: now)
        
        // Insert a row into the `items` relation
        items.asyncAdd([
            Item.id.attribute: id,
            Item.title.attribute: title,
            Item.created.attribute: now,
            Item.status.attribute: status,
            Item.notes.attribute: ""
        ])
    }
    
    /// REQ-1
    /// Adds a new row to the `items` relation.  This is an undoable action.
    func addNewItem(with title: String) {
        undoableDB.performUndoableAction("Add Item", {
            self.addItem(title)
        })
    }

    /// REQ-3 / REQ-7
    /// Returns a property that reflects the completed status for the given relation.
    func itemCompleted(_ relation: Relation, initialValue: String?) -> AsyncReadWriteProperty<CheckState> {
        return relation.undoableTransformedString(
            undoableDB, "Change Status", initialValue: initialValue,
            fromString: { CheckState(parseCompleted($0)) },
            toString: { statusString(pending: $0 != .on, timestamp: timestampString()) }
        )
    }

    /// REQ-4 / REQ-8
    /// Returns a property that reflects the item title.
    func itemTitle(_ relation: Relation, initialValue: String?) -> AsyncReadWriteProperty<String> {
        return relation.undoableOneString(undoableDB, "Change Title", initialValue: initialValue)
    }

    // MARK: - List Selection
    
    /// REQ-6
    /// Resolves to the item that is selected in the list of to-do items.
    lazy var selectedItems: Relation = {
        return self.selectedItemIDs.join(self.items)
    }()
    
    /// REQ-6
    /// Resolves to `true` when an item is selected in the list of to-do items.
    lazy var hasSelection: AsyncReadableProperty<Bool> = {
        return self.selectedItems.nonEmpty.property()
    }()
    
    // MARK: - Tags
    
    /// REQ-5
    /// Returns a property that resolves to a string containing a comma-separated
    /// list of tags that have been applied to the given to-do item.
    func tagsString(for itemID: ItemID) -> AsyncReadableProperty<String> {
        return self.itemTags
            .select(ItemTag.itemID.self *== itemID)
            .join(self.tags)
            .project(Tag.name.self)
            .allValues()
            .map{ $0.sorted().joined(separator: ", ") }
            .property()
    }
    
    /// REQ-9
    /// Resolves to the set of tags that are associated with the selected to-do
    /// item (assumes there is either zero or one selected items).
    lazy var tagsForSelectedItem: Relation = {
        return self.selectedItemIDs
            .join(self.itemTags)
            .join(self.tags)
            .project([Tag.id.attribute, Tag.name.attribute])
    }()

    /// REQ-9
    /// Resolves to the set of tags that are not yet associated with the
    /// selected to-do item, i.e., the available tags.
    lazy var availableTagsForSelectedItem: Relation = {
        // This is simply "all tags" minus "already applied tags", nice!
        return self.tags
            .difference(self.tagsForSelectedItem)
    }()

    /// REQ-9
    /// Adds a new row to the `tags` relation.
    private func addTag(_ name: String) {
        let id = TagID()
        
        tags.asyncAdd([
            Tag.id.attribute: id,
            Tag.name.attribute: name
        ])
    }
    
    /// REQ-9
    /// Creates a new tag and applies it to the given to-do item.
    func addNewTag(named name: String, to itemID: ItemID) {
        let tagID = TagID()
        
        undoableDB.performUndoableAction("Add New Tag", {
            self.tags.asyncAdd([
                Tag.id.attribute: tagID,
                Tag.name.attribute: name
            ])
            
            self.itemTags.asyncAdd([
                ItemTag.itemID.attribute: itemID,
                ItemTag.tagID.attribute: tagID
            ])
        })
    }

    /// REQ-9
    /// Applies an existing tag to the given to-do item.
    func addExistingTag(_ tagID: TagID, to itemID: ItemID) {
        undoableDB.performUndoableAction("Add Tag", {
            self.itemTags.asyncAdd([
                ItemTag.itemID.attribute: itemID,
                ItemTag.tagID.attribute: tagID
            ])
        })
    }
    
    /// REQ-10
    /// Returns a property that reflects the tag name.
    func tagName(for tagID: TagID, initialValue: String?) -> AsyncReadWriteProperty<String> {
        return self.tags
            .select(Tag.id.self *== tagID)
            .project(Tag.name.self)
            .undoableOneValue(undoableDB, "Change Tag Name", initialValue: initialValue)
    }
    
    // MARK: - Notes
    
    /// REQ-11
    /// Returns a property that reflects the selected item's notes.
    lazy var selectedItemNotes: AsyncReadWriteProperty<String> = {
        return self.selectedItems
            .project(Item.notes.self)
            .undoableOneValue(self.undoableDB, "Change Notes")
    }()
    
    // MARK: - Delete
    
    /// REQ-13
    /// Deletes the row associated with the selected item and
    /// clears the selection.  This demonstrates the use of
    /// `cascadingDelete`, which is kind of overkill for this
    /// particular case but does show how easy it can be to
    /// clean up related data with a single call.
    func deleteSelectedItem() {
        undoableDB.performUndoableAction("Delete Item", {
            // We initiate the cascading delete by first removing
            // all rows from `selectedItemIDs`
            self.selectedItemIDs.cascadingDelete(
                true, // `true` here means "all rows"
                affectedRelations: [
                    self.items, self.selectedItemIDs, self.itemTags
                ],
                cascade: { (relation, row) in
                    if relation === self.selectedItemIDs {
                        // This row was deleted from `selectedItemIDs`;
                        // delete corresponding rows from `items`
                        // and `itemTags`
                        let itemID = ItemID(row)
                        return [
                            (self.items, Item.id.self *== itemID),
                            (self.itemTags, ItemTag.itemID.self *== itemID)
                        ]
                    } else {
                        // Nothing else to clean up
                        return []
                    }
                }
            )
        })
    }
}

private let timestampFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f
}()

private func timestampString() -> String {
    return timestampFormatter.string(from: Date())
}

private let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .none
    return f
}()

func displayString(from timestampString: String) -> String {
    let date = timestampFormatter.date(from: timestampString) ?? Date()
    return dateFormatter.string(from: date)
}

private func statusString(pending: Bool, timestamp: String) -> String {
    return "\(pending ? 1 : 0) \(timestamp)"
}

private func parseCompleted(_ status: String) -> Bool {
    return status.hasPrefix("0")
}
