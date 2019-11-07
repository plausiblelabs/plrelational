//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import Combine
import PLRelational
import PLRelationalCombine

private typealias Spec = PlistDatabase.RelationSpec

/// Scheme for the `item` relation that holds the to-do items.
enum Item {
    static let id = Attribute("item_id")
    static let title = Attribute("title")
    static let created = Attribute("created")
    static let status = Attribute("status")
    static let notes = Attribute("notes")
    fileprivate static var spec: Spec { return .file(
        name: "item",
        path: "items.plist",
        scheme: [id, title, created, status, notes],
        primaryKeys: [id]
    )}
}

/// Scheme for the `tag` relation that holds the named tags.
enum Tag {
    static let id = Attribute("tag_id")
    static let name = Attribute("name")
    fileprivate static var spec: Spec { return .file(
        name: "tag",
        path: "tags.plist",
        scheme: [id, name],
        primaryKeys: [id]
    )}
}

/// Scheme for the `item_tag` relation that associates zero
/// or more tags with a to-do item.
enum ItemTag {
    static let itemID = Item.id
    static let tagID = Tag.id
    fileprivate static var spec: Spec { return .file(
        name: "item_tag",
        path: "item_tags.plist",
        scheme: [itemID, tagID],
        primaryKeys: [itemID, tagID]
    )}
}

/// Scheme for the `selected_item` relation that maintains
/// the selection state for the list of to-do items.
enum SelectedItem {
    static let id = Item.id
    fileprivate static var spec: Spec { return .transient(
        name: "selected_item",
        scheme: [id],
        primaryKeys: [id]
    )}
}

class Model {
    
    let items: TransactionalRelation
    let tags: TransactionalRelation
    let itemTags: TransactionalRelation
    let selectedItemIDs: TransactionalRelation

    var allTags: [RowArrayElement] = []
    
    private let db: TransactionalDatabase
    let undoableDB: UndoableDatabase

    private var cancellableBag = Set<AnyCancellable>()

    init(undoManager: PLRelationalCombine.UndoManager) {
        let specs: [Spec] = [
            Item.spec,
            Tag.spec,
            ItemTag.spec,
            SelectedItem.spec
        ]

        // Create a database or open an existing one (stored on disk using plists)
        // TODO: In Catalina we can no longer access /tmp directly; should use a better temp path here
        let path = "~/tmp/TodoSwiftUIApp.db"
        // XXX: Start with a fresh database each time, for now
        _ = try? FileManager.default.removeItem(atPath: path)
        let dbExisted = FileManager.default.fileExists(atPath: path)
        let plistDB = PlistDatabase.create(URL(fileURLWithPath: path), specs).ok!

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
        tags
            .sortedRows(idAttr: Tag.id, orderAttr: Tag.name)
            .replaceError(with: [])
            .assign(to: \.allTags, on: self)
            .store(in: &cancellableBag)

//        if !dbExisted {
            // Add a couple default tags
//            addTag("home")
//            addTag("work")
//            addTag("school")
//            addTag("urgent")
//        }
    }

    deinit {
        cancellableBag.forEach{ $0.cancel() }
    }
    
    /// MARK: - Items
    
    /// Adds a new row to the `items` relation.
    private func addItem(_ title: String, created: Date) -> ItemID {
        // Use UUIDs to uniquely identify rows.  Note that we can pass `id` directly
        // when initializing the row because `ItemID` conforms to the
        // `RelationValueConvertible` protocol.
        let id = ItemID()

        // Use a string representation of the current time to make our life easier
        let timestamp = timestampString(from: created)
        
        // Here we cheat a little.  ArrayProperty currently only knows how to sort
        // on a single attribute (temporary limitation), we cram two things -- the
        // completed flag and the timestamp of the action -- into a single string of
        // the form "<0/1> <timestamp>".  This allows us to keep to-do items sorted
        // in the list with pending items at top and completed ones at bottom.
        let status = statusString(pending: true, timestamp: timestamp)
        
        // Insert a row into the `items` relation
        items.asyncAdd([
            Item.id: id,
            Item.title: title,
            Item.created: timestamp,
            Item.status: status,
            Item.notes: ""
        ])
        
        return id
    }
    
    /// Adds a new row to the `items` relation.  This is an undoable action.
    func addNewItem(with title: String, created: Date = Date()) -> ItemID {
        var itemID: ItemID!
        undoableDB.performUndoableAction("Add Item", {
            itemID = self.addItem(title, created: created)
        })
        return itemID
    }

//    /// Returns a property that reflects the completed status for the given relation.
//    func itemCompleted(_ relation: Relation, initialValue: String?) -> AsyncReadWriteProperty<CheckState> {
//        return relation.undoableTransformedString(
//            undoableDB, "Change Status", initialValue: initialValue,
//            fromString: { CheckState(parseCompleted($0)) },
//            toString: { statusString(pending: $0 != .on, timestamp: timestampString()) }
//        )
//    }

//    /// REQ-4 / REQ-8
//    /// Returns a property that reflects the item title.
//    func itemTitle(_ relation: Relation, initialValue: String?) -> AsyncReadWriteProperty<String> {
//        return relation.undoableOneString(undoableDB, "Change Title", initialValue: initialValue)
//    }

//    /// REQ-4 / REQ-8
//    /// Returns a binding that reflects the item title.
//    func itemTitle(_ relation: Relation) -> Binding<String> {
//        return relation.undoableOneString(undoableDB, "Change Title")
//    }

    // MARK: - List Selection
    
    /// Resolves to the item that is selected in the list of to-do items.
    lazy var selectedItems: Relation = {
        return self.selectedItemIDs.join(self.items)
    }()
    
    // MARK: - Tags
    
    /// Returns a Publisher that resolves to a string containing a comma-separated
    /// list of tags that have been applied to the given to-do item.
    func tagsString(for itemID: ItemID) -> AnyPublisher<String, Never> {
        return self.itemTags
            .select(ItemTag.itemID *== itemID)
            .join(self.tags)
            .project(Tag.name)
            .allStrings()
            .replaceError(with: Set()) // XXX: We'll ignore errors at this level for now
            .map{ $0.sorted().joined(separator: ", ") }
            .eraseToAnyPublisher()
    }
    
    /// Resolves to the set of tags that are associated with the selected to-do
    /// item (assumes there is either zero or one selected items).
    lazy var tagsForSelectedItem: Relation = {
        return self.selectedItemIDs
            .join(self.itemTags)
            .join(self.tags)
            .project([Tag.id, Tag.name])
    }()

    /// Resolves to the set of tags that are not yet associated with the
    /// selected to-do item, i.e., the available tags.
    lazy var availableTagsForSelectedItem: Relation = {
        // This is simply "all tags" minus "already applied tags", nice!
        return self.tags
            .difference(self.tagsForSelectedItem)
    }()

    /// Adds a new row to the `tags` relation.
    private func addTag(_ name: String) {
        let id = TagID()
        
        tags.asyncAdd([
            Tag.id: id,
            Tag.name: name
        ])
    }
    
    /// Creates a new tag and applies it to the given to-do item.
    func addNewTag(named name: String, to itemID: ItemID) {
        let tagID = TagID()
        
        undoableDB.performUndoableAction("Add New Tag", {
            self.tags.asyncAdd([
                Tag.id: tagID,
                Tag.name: name
            ])
            
            self.itemTags.asyncAdd([
                ItemTag.itemID: itemID,
                ItemTag.tagID: tagID
            ])
        })
    }

    /// Applies an existing tag to the given to-do item.
    func addExistingTag(_ tagID: TagID, to itemID: ItemID) {
        undoableDB.performUndoableAction("Add Tag", {
            self.itemTags.asyncAdd([
                ItemTag.itemID: itemID,
                ItemTag.tagID: tagID
            ])
        })
    }
    
//    /// Returns a property that reflects the tag name.
//    func tagName(for tagID: TagID, initialValue: String?) -> AsyncReadWriteProperty<String> {
//        return self.tags
//            .select(Tag.id *== tagID)
//            .project(Tag.name)
//            .undoableOneString(undoableDB, "Change Tag Name", initialValue: initialValue)
//    }
//    
//    // MARK: - Notes
//    
//    /// Returns a property that reflects the selected item's notes.
//    lazy var selectedItemNotes: AsyncReadWriteProperty<String> = {
//        return self.selectedItems
//            .project(Item.notes)
//            .undoableOneString(self.undoableDB, "Change Notes")
//    }()
    
    // MARK: - Delete
    
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
                            (self.items, Item.id *== itemID),
                            (self.itemTags, ItemTag.itemID *== itemID)
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

private func timestampString(from date: Date) -> String {
    return timestampFormatter.string(from: date)
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

#if DEBUG
func modelForPreview() -> Model {
    let undoManager = PLRelationalCombine.UndoManager()
    let model = Model(undoManager: undoManager)
    
    let item1 = model.addNewItem(with: "Item 1")
    model.addNewTag(named: "home", to: item1)
    model.addNewTag(named: "urgent", to: item1)

    let item2 = model.addNewItem(with: "Item 2")
    model.addNewTag(named: "personal", to: item2)

    // XXX: Select an item (this is a hack just for testing out Combine stuff)
    model.selectedItemIDs.asyncAdd([
        SelectedItem.id: item1
    ])

    return model
}
#endif
