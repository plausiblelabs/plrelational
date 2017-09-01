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
    static let title = Attribute("title")
    static let created = Attribute("created")
    static let status = Attribute("status")
    static let notes = Attribute("notes")
    fileprivate static var spec: Spec { return .file(name: "item", path: "items.plist", scheme: [id, title, created, status, notes], primaryKeys: [id]) }
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

    let allTags: AsyncReadableProperty<[RowArrayElement]>
    
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

        // Keep the set of all tags cached for easy access
        self.allTags = tags
            .arrayProperty(idAttr: Tag.id, orderAttr: Tag.name)
            .fullArray()
        self.allTags.start()

        // XXX: Temporarily add some initial data for testing purposes
        addItem("One")
        addItem("Two")
        addItem("Three")
        
        // Add a couple default tags
        // TODO: Only do this if creating the database for the first time
        addTag("home")
        addTag("work")
        addTag("urgent")
    }

    /// MARK: - Undo Support
    
    func undoableBidiProperty<T>(action: String, signal: Signal<T>, update: @escaping (T) -> Void) -> AsyncReadWriteProperty<T> {
        return undoableDB.bidiProperty(action: action, signal: signal, update: update)
    }
    
    func performUndoableAction(_ name: String, _ transactionFunc: @escaping (Void) -> Void) {
        undoableDB.performUndoableAction(name, before: nil, transactionFunc)
    }
    
    /// Adds a new row to the `items` relation.
    private func addItem(_ title: String) {
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
        let status = RelationValue(statusString(pending: true, timestamp: now))
        
        items.asyncAdd([
            Item.id: id,
            Item.title: RelationValue(title),
            Item.created: created,
            Item.status: status,
            Item.notes: RelationValue("")
        ])
    }
    
    /// Adds a new row to the `items` relation.  This is an undoable action.
    func addNewItem(with title: String) {
        performUndoableAction("New Item", {
            self.addItem(title)
        })
    }
    
    /// Adds a new row to the `tags` relation.
    private func addTag(_ name: String) {
        // Use UUIDs to uniquely identify rows
        let id = RelationValue(uuidString())
        
        tags.asyncAdd([
            Tag.id: id,
            Tag.name: RelationValue(name)
        ])
    }
    
    // MARK: - Selected Item
    
    /// Resolves to `true` when an item is selected in the list of to-do items.
    lazy var hasSelection: AsyncReadableProperty<Bool> = {
        return self.selectedItems.nonEmpty.property()
    }()
    
    /// Resolves to the item that is selected in the list of to-do items.
    lazy var selectedItems: Relation = {
        return self.selectedItemIDs.join(self.items)
    }()
    
    /// Returns a property that reflects the item title.
    func itemTitle(_ relation: Relation, initialValue: String?) -> AsyncReadWriteProperty<String> {
        return self.undoableBidiProperty(
            action: "Change Item Title",
            signal: relation.oneString(initialValue: initialValue),
            update: {
                relation.asyncUpdateString($0)
            }
        )
    }

    /// Returns a property that reflects the selected item's notes.
    lazy var selectedItemNotes: AsyncReadWriteProperty<String> = {
        let relation = self.selectedItems.project(Item.notes)
        return self.undoableBidiProperty(
            action: "Change Notes",
            signal: relation.oneString(),
            update: {
                relation.asyncUpdateString($0)
            }
        )
    }()

    /// Deletes the row associated with the selected item and clears the selection.  This demonstrates
    /// the use of `cascadingDelete`, which is kind of overkill for this particular case but does show
    /// how easy it can be to clean up related data.
    func deleteSelectedItem() {
        performUndoableAction("Delete Item", {
            // We initiate the cascading delete by removing all rows from `selectedItemIDs`
            self.selectedItemIDs.cascadingDelete(
                true, // `true` here means "all rows"
                affectedRelations: [self.items, self.selectedItemIDs, self.itemTags],
                cascade: { (relation, row) in
                    if relation === self.selectedItemIDs {
                        // This row was deleted from `selectedItemIDs`; delete corresponding rows from
                        // `items` and `itemTags`
                        let itemID = row[SelectedItem.id]
                        return [
                            (self.items, Item.id *== itemID),
                            (self.itemTags, ItemTag.itemID *== itemID)
                        ]
                    } else {
                        // Nothing else to clean up
                        return []
                    }
                },
                update: { _ in return [] },
                completionCallback: { _ in }
            )
        })
    }
    
    // MARK: - Tags
    
    /// Resolves to the set of tags that are associated with the selected to-do item
    /// (assumes there is either zero or one selected items).
    lazy var tagsForSelectedItem: Relation = {
        return self.selectedItemIDs
            .join(self.itemTags)
            .join(self.tags)
            .project([Tag.id, Tag.name])
    }()
    
    /// Resolves to the set of tags that are not yet associated with the selected to-do
    /// item, i.e., the available tags.
    lazy var availableTagsForSelectedItem: Relation = {
        // This is simply "all tags" minus "already applied tags", nice!
        return self.tags
            .difference(self.tagsForSelectedItem)
    }()

    /// Returns a property that reflects the tag name.
    func tagName(for tagID: String, initialValue: String?) -> AsyncReadWriteProperty<String> {
        let tagNameRelation = self.tags
            .select(Tag.id *== RelationValue(tagID))
            .project(Tag.name)
        return self.undoableBidiProperty(
            action: "Change Tag Name",
            signal: tagNameRelation.oneString(initialValue: initialValue),
            update: {
                tagNameRelation.asyncUpdateString($0)
            }
        )
    }
    
    /// Returns a property that resolves to a string containing a comma-separated list
    /// of tags that have been applied to the given to-do item.
    func tagsString(for itemID: String) -> AsyncReadableProperty<String> {
        return self.itemTags
            .select(Item.id *== RelationValue(itemID))
            .join(self.tags)
            .arrayProperty(idAttr: Tag.id, orderAttr: Tag.name)
            .fullArray()
            .map{ elems in
                return elems.map{ elem -> String in elem.data[Tag.name].get()! }.joined(separator: ", ")
            }
    }
    
    /// Creates a new tag and applies it to the given to-do item.
    func addNewTag(named name: String, to itemID: String) {
        // TODO: Create ItemID and TagID value types
        let tagID = RelationValue(uuidString())
        
        performUndoableAction("Add New Tag", {
            self.tags.asyncAdd([
                Tag.id: tagID,
                Tag.name: RelationValue(name)
            ])
            
            self.itemTags.asyncAdd([
                ItemTag.itemID: RelationValue(itemID),
                ItemTag.tagID: tagID
            ])
        })
    }
    
    /// Applies an existing tag to the given to-do item.
    func addExistingTag(_ tagID: String, to itemID: String) {
        performUndoableAction("Add Tag", {
            self.itemTags.asyncAdd([
                ItemTag.itemID: RelationValue(itemID),
                ItemTag.tagID: RelationValue(tagID)
            ])
        })
    }
}

private func uuidString() -> String {
    return UUID().uuidString
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
    let date = timestampFormatter.date(from: timestampString)!
    return dateFormatter.string(from: date)
}

private func statusString(pending: Bool, timestamp: String) -> String {
    return "\(pending ? 1 : 0) \(timestamp)"
}
