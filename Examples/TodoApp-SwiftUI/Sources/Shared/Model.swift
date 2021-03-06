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
    static let completed = Attribute("completed")
    static let notes = Attribute("notes")
    fileprivate static var spec: Spec { return .file(
        name: "item",
        path: "items.plist",
        scheme: [id, title, created, completed, notes],
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

struct ExistingTag {
    let id: TagID
    let name: String
    
    init(row: Row) {
        self.id = TagID(row)
        self.name = row[Tag.name].get()!
    }
}

class Model {
    
    let items: TransactionalRelation
    let tags: TransactionalRelation
    let itemTags: TransactionalRelation
    let selectedItemIDs: TransactionalRelation

    private(set) var allTags: [ExistingTag] = []
    
    let dbAlreadyExisted: Bool
    private let db: TransactionalDatabase
    private let undoableDB: UndoableDatabase

    private var cancellableBag = CancellableBag()

    init(undoManager: PLRelationalCombine.UndoManager, path: String?) {
        let specs: [Spec] = [
            Item.spec,
            Tag.spec,
            ItemTag.spec,
            SelectedItem.spec
        ]

        let dbUrl: URL?
        if let path = path {
            // Create a database or open an existing one (stored on disk using plists)
            dbUrl = URL(fileURLWithPath: path)
            
            // Set a flagAdd some default data the first time the database is created
            dbAlreadyExisted = FileManager.default.fileExists(atPath: path)
        } else {
            // When path is nil, we will create an in-memory (plist compatible) database
            // only, which is useful for previews
            dbUrl = nil
            
            // Always add default data in this case
            dbAlreadyExisted = false
        }
        let plistDB = PlistDatabase.create(dbUrl, specs).ok!

        // Wrap it in a TransactionalDatabase so that we can use snapshots
        let db = TransactionalDatabase(plistDB)
        if dbUrl != nil {
            // Enable auto-save so that all changes are persisted to disk as needed
            db.saveOnTransactionEnd = true
        }
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
            .map(ExistingTag.init, sortedBy: \.name)
            .replaceError(with: [])
            .bind(to: \.allTags, on: self)
            .store(in: &cancellableBag)
    }

    deinit {
        cancellableBag.cancel()
    }

    func addDefaultData(selectItem: Bool = false) -> [ItemID] {
        // Add a couple default tags
        let tagHome = addTag("home")
        let tagWork = addTag("work")
        let tagUrgent = addTag("urgent")
        _ = addTag("school")

        func addExisting(tag: TagID, to item: ItemID) {
            self.itemTags.asyncAdd([
                ItemTag.itemID: item,
                ItemTag.tagID: tag
            ])
        }
        
        // Also add some default items
        let item1 = addItem("Item 1", created: Date(timeIntervalSinceNow: -3600 * 72))
        addExisting(tag: tagHome, to: item1)
        addExisting(tag: tagUrgent, to: item1)
        let item2 = addItem("Item 2", created: Date(timeIntervalSinceNow: -3600 * 48))
        addExisting(tag: tagWork, to: item2)
        let item3 = addItem("Item 3", created: Date(timeIntervalSinceNow: -3600 * 24))

        if selectItem {
            selectedItemIDs.asyncAdd([
                SelectedItem.id: item1
            ])
        }
        
        return [item1, item2, item3]
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
        
        // Insert a row into the `items` relation
        items.asyncAdd([
            Item.id: id,
            Item.title: title,
            Item.created: timestamp,
            Item.completed: RelationValue.null,
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
    
    /// REQ-3 / REQ-7
    /// Returns a TwoWayStrategy that allows for changing the completed status of an item.
    func itemCompleted() -> (Relation, InitiatorTag) -> UndoableOneValueStrategy<Bool> {
        // This is an example of an "asymmetric" two-way binding scenario.  In our `item` relation,
        // the `completed` column contains a timestamp for when the item was marked as completed,
        // or it will be `.null` if the item is not yet completed.  However, we want to be able
        // to use a checkbox to control this value, so we use `UndoableOneValueStrategy` with
        // custom read/update functions.  The read will resolve to true when the timestamp is
        // defined, and false otherwise.  The update will store the current timestamp string
        // when the value is true, but will store `.null` when the value if false.
        return { relation, initiator in
            precondition(relation.scheme.attributes.count == 1, "Relation must contain exactly one attribute")
            let reader: TwoWayReader<Bool> = TwoWayReader(defaultValue: false, valueFromRows: { rows in
                relation.extractOneValue(from: AnyIterator(rows.makeIterator()), { $0.get() as String? != nil }, orDefault: false)
            })
            let update = { (newValue: Bool) in
                relation.asyncUpdateNullableString(newValue ? timestampString(from: Date()) : nil)
            }
            return UndoableOneValueStrategy(undoableDB: self.undoableDB, action: "Change Status", relation: relation,
                                            reader: reader, updateFunc: update)
        }
    }

    /// REQ-4 / REQ-8
    /// Returns a TwoWayStrategy that allows for changing the title of an item.
    func itemTitle() -> (Relation, InitiatorTag) -> UndoableOneValueStrategy<String> {
        return undoableDB.oneString("Change Title")
    }

    /// REQ-11
    /// Returns a TwoWayStrategy that allows for changing the notes of an item.
    func itemNotes() -> (Relation, InitiatorTag) -> UndoableOneValueStrategy<String> {
        return undoableDB.oneString("Change Notes")
    }

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
    
    /// Resolves to the set of all tags, including an extra column that will contain
    /// the selected item's ID if it is associated with the tag, otherwise null.
    lazy var allTagsWithSelectedItemID: Relation = {
        // Compute relation of all tags associated with the selected item
        let allTagsForSelectedItem = self.selectedItemIDs
            .join(self.itemTags)
        
        return self.tags
            .leftOuterJoin(allTagsForSelectedItem)
    }()

    /// Adds a new row to the `tags` relation.
    private func addTag(_ name: String) -> TagID {
        let id = TagID()
        
        tags.asyncAdd([
            Tag.id: id,
            Tag.name: name
        ])
        
        return id
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

    /// Removes an existing tag from the given to-do item.
    func removeExistingTag(_ tagID: TagID, from itemID: ItemID) {
        undoableDB.performUndoableAction("Remove Tag", {
            self.itemTags.asyncDelete(
                ItemTag.itemID *== itemID.relationValue *&&
                ItemTag.tagID *== tagID.relationValue
            )
        })
    }

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
    
    /// Deletes the row associated with the given item and
    /// clears the selection.
    func deleteItem(_ itemID: ItemID) {
        undoableDB.performUndoableAction("Delete Item", {
            // We initiate the cascading delete by first removing
            // the row from the `items` relation
            self.items.cascadingDelete(
                Item.id *== itemID,
                affectedRelations: [
                    self.items, self.selectedItemIDs, self.itemTags
                ],
                cascade: { (relation, row) in
                    if relation === self.items {
                        // This row was deleted from `items`; delete
                        // corresponding rows from `selectedItemIDs`
                        // and `itemTags`
                        return [
                            (self.selectedItemIDs, SelectedItem.id *== itemID),
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

struct ChecklistItem: Identifiable {
    let id: ItemID
    let title: String
    let created: String
    let completed: String?
    
    init(id: ItemID, title: String, created: String, completed: String?) {
        self.id = id
        self.title = title
        self.created = created
        self.completed = completed
    }
    
    init(row: Row) {
        self.id = ItemID(row[Item.id])
        self.title = row[Item.title].get()!
        self.created = row[Item.created].get()!
        self.completed = row[Item.completed].get()
    }
}

func itemOrder(_ a: ChecklistItem, _ b: ChecklistItem) -> Bool {
    // We sort items into two sections:
    //   - first section has all incomplete items, with most recently created items at the top
    //   - second section has all completed items, with most recently completed items at the top
    if let aCompleted = a.completed, let bCompleted = b.completed {
        // Both items were completed; make more recently completed item come first
        return aCompleted >= bCompleted
    } else if a.completed != nil {
        // `a` was completed but `b` was not, so `a` will come after `b`
        return false
    } else if b.completed != nil {
        // `b` was completed but `a` was not, so `b` will come after `a`
        return true
    } else {
        // Neither item was completed; make more recently created item come first
        return a.created >= b.created
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

#if DEBUG
func modelForPreviewWithIds() -> (Model, [ItemID]) {
    let undoManager = PLRelationalCombine.UndoManager()
    let model = Model(undoManager: undoManager, path: nil)
    let itemIds = model.addDefaultData(selectItem: true)
    return (model, itemIds)
}
func modelForPreview() -> Model {
    return modelForPreviewWithIds().0
}
#endif
