//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import PLRelational
import PLRelationalBinding
import PLBindableControls

class ViewModel {
    
    private let persons: Relation
    private let personBios: Relation
    private let selectedPersonID: TransactionalRelation
    private let selectedPerson: Relation

    private let transactionalDB: TransactionalDatabase
    private let undoableDB: UndoableDatabase
    
    init(undoManager: PLRelationalBinding.UndoManager) {
        
        func makeDB() -> (path: String, db: SQLiteDatabase) {
            let tmp = "/tmp" as NSString
            let dbname = "SearchApp.db"
            let path = tmp.appendingPathComponent(dbname)
            _ = try? FileManager.default.removeItem(atPath: path)
            
            let db = try! SQLiteDatabase(path)
            
            return (path, db)
        }
        
        // Prepare the stored relations
        let sqliteDB = makeDB().db
        let transactionalDB = TransactionalDatabase(sqliteDB)
        func createRelation(_ name: String, _ scheme: Scheme) -> TransactionalRelation {
            let createResult = sqliteDB.createRelation(name, scheme: scheme)
            precondition(createResult.ok != nil)
            return transactionalDB[name]
        }
        persons = createRelation("person", ["id", "name"])
        personBios = createRelation("person_bio", ["id", "bio"])
        selectedPersonID = createRelation("selected_person", ["id"])
        
        selectedPerson = selectedPersonID
            .join(persons)
            .join(personBios)

        self.undoableDB = UndoableDatabase(db: transactionalDB, undoManager: undoManager)
        self.transactionalDB = transactionalDB

        // Add some persons
        func addPerson(_ id: Int64, _ name: String, _ bio: String) {
            let personRow: Row = [
                "id": RelationValue(id),
                "name": RelationValue(name)
            ]
            _ = sqliteDB["person"]!.add(personRow)
            
            let bioRow: Row = [
                "id": RelationValue(id),
                "bio": RelationValue(bio)
            ]
            _ = sqliteDB["person_bio"]!.add(bioRow)
        }
        addPerson(1, "Montgomery Burns", "Owner, Springfield Nuclear Power Plant.  His full name is Charles Montgomery Burns, sometimes shortened as C.M. Burns or Monty Burns, but his employees call him Mr. Burns.  He is the richest man in Springfield.")
        addPerson(2, "Waylon Smithers", "Personal assistant to Mr. Burns.  Smithers is a character that is known for things like this and that and this and that and this and that.")
        addPerson(3, "Homer Simpson", "Safety inspector at Springfield Nuclear Power Plant, Sector 7G.  Homer is best known for saying things like \"D'oh!\" and eating donuts.")
        addPerson(4, "Lenny Leonard", "Friend to Homer and Carl.  Lenny is a character that is known for things like this and that and this and that and this and that.")
        addPerson(5, "Carl Carlson", "Friend to Homer and Lenny.  Carl is a character that is known for things like this and that and this and that and this and that.")
    }
    
    private lazy var searchIndex: RelationTextIndex = {
        let personIDs = self.persons
            .project("id")
        let personBioData = self.persons
            .join(self.personBios)
        
        func columnConfig(_ attribute: Attribute, _ textExtractor: @escaping (Row) -> Result<String, RelationError>) -> RelationTextIndex.ColumnConfig {
            return RelationTextIndex.ColumnConfig(snippetAttribute: attribute, textExtractor: textExtractor)
        }
        
        let nameConfig = columnConfig(SearchResult.personNameAttribute, { (row: Row) in
            return .Ok(row["name"].get()!)
        })
        
        let bioConfig = columnConfig(SearchResult.personBioAttribute, { (row: Row) in
            return .Ok(row["bio"].get()!)
        })
        
        return try! RelationTextIndex(ids: (personIDs, "id"), content: (personBioData, "id"), columnConfigs: [nameConfig, bioConfig])
    }()
    
    private lazy var searchResults: RelationTextIndex.SearchRelation = {
        return self.searchIndex.search("")
    }()
    
    private lazy var resultsArray: ArrayProperty<RowArrayElement> = {
        return self.searchResults.arrayProperty(idAttr: "id", orderAttr: "rank", descending: true)
    }()
    
    lazy var queryString: ReadWriteProperty<String> = {
        return mutableValueProperty("", { query, _ in
            self.searchResults.query = "\(query)*"
        })
    }()

    lazy var resultsListModel: ListViewModel<RowArrayElement> = {
        return ListViewModel(
            data: self.resultsArray,
            contextMenu: nil,
            move: nil,
            cellIdentifier: { _ in "Cell" }
        )
    }()
    
    lazy var resultsListSelection: AsyncReadWriteProperty<Set<RelationValue>> = {
        return self.bidiProperty(
            signal: self.selectedPersonID.allRelationValues(),
            update: { self.selectedPersonID.asyncReplaceValues(Array($0)) }
        )
    }()
    
    lazy var hasResults: AsyncReadableProperty<Bool> = {
        return self.searchResults.nonEmpty.property()
    }()

    lazy var selectedPersonName: AsyncReadableProperty<String> = {
        return self.selectedPerson
            .project("name")
            .oneStringOrNil()
            .property()
            .map{ $0 ?? "No selection" }
    }()

    lazy var selectedPersonBio: AsyncReadableProperty<String> = {
        return self.selectedPerson
            .project("bio")
            .oneString()
            .property()
    }()

    private func bidiProperty<T>(signal: Signal<T>, update: @escaping (T) -> Void) -> AsyncReadWriteProperty<T> {
        let config = asyncMutationConfig(update)
        return signal.property(mutator: config)
    }
    
    private func asyncMutationConfig<T>(_ update: @escaping (T) -> Void) -> RelationMutationConfig<T> {
        return RelationMutationConfig(
            snapshot: {
                // TODO: Make snapshot optional; we don't actually use it for non-undoable properties
                return self.transactionalDB.takeSnapshot()
            },
            update: { newValue in
                update(newValue)
            },
            commit: { _, newValue in
                update(newValue)
            }
        )
    }
}
