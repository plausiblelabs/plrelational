//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

import sqlite3


/// An index for fast full-text searches of large quantities of text.
/// Manages two Relations which provide the text and related info,
/// and provides Relations which provide search results.
public class RelationTextIndex {
    fileprivate enum State {
        case notLoaded
        case loadingIDs
        case loadingContent(idsToLoad: Set<RelationValue>)
        case loaded
    }
    
    public enum Error: RelationError {
        case consistencyError(String)
    }
    
    fileprivate let idRelation: Relation
    fileprivate let idAttribute: Attribute
    
    fileprivate let contentRelation: Relation
    fileprivate let contentIDAttribute: Attribute
    
    fileprivate let db: SQLiteDatabase
    
    fileprivate var state = State.notLoaded
    
    fileprivate let searchRelations = NSHashTable<SearchRelation>.weakObjects()
    
    fileprivate var observationRemover: AsyncManager.ObservationRemover?
    
    fileprivate let runloop: CFRunLoop
    
    fileprivate let columnConfigs: [ColumnConfig]
    
    fileprivate let columnNames: [String]
    
    fileprivate let searchRelationScheme: Scheme
    
    /// Initialize a new index object.
    ///
    /// - Parameters:
    ///   - ids: A Relation which provides page IDs, and the attribute for the IDs.
    ///          This is used to get the initial list of pages.
    ///   - content: A Relation which provides page content and IDs, plus the attribute
    ///              for the IDs.
    ///   - contentTextExtractor: A function which, given a Row from the content
    ///                           Relation, returns the text that row contains.
    /// - Throws: SQLiteDatabase.Error if something went wrong with SQLite setup.
    public init(ids: (Relation, Attribute), content: (Relation, Attribute), columnConfigs: [ColumnConfig]) throws {
        (idRelation, idAttribute) = ids
        (contentRelation, contentIDAttribute) = content
        self.columnConfigs = columnConfigs
        
        columnNames = columnConfigs.indices.map({ "text_\($0)" })
        
        let snippetAttributes = columnConfigs.map({ $0.snippetAttribute })
        searchRelationScheme = Scheme(attributes: Set([contentIDAttribute, "rank"] + snippetAttributes))
        
        runloop = CFRunLoopGetCurrent()
        
        db = try SQLiteDatabase("")
        
        try setupTokenizer(db: db).orThrow()
        
        sqlite3_create_function(db.db, "rank", 1, SQLITE_ANY, nil, rank, nil, nil)
        
        try db.executeQueryWithEmptyResults("CREATE TABLE \(pagesTable) (\(Attribute.pageID))").orThrow()
        // TODO: we want a contentless table with `content=\"\", ` but FTS4 doesn't support deletion from them.
        // If we build our own SQLite we can use FTS5 which does. Alternately: external content table with
        // a virtual table.
        let columns = (["tokenize=\(tokenizerName)"] + columnNames).joined(separator: ", ")
        try db.executeQueryWithEmptyResults("CREATE VIRTUAL TABLE \(contentTable) USING fts4(\(columns))").orThrow()
    }
    
    deinit {
        observationRemover?()
    }
    
    /// Return a Relation which contains matches for the given query.
    ///
    /// - Parameter query: The query, using SQLite FTS4 syntax.
    /// - Returns: A Relation containing the IDs of matching entries. It contains only
    ///            IDs, under the ID attribute provided for the content relation passed
    ///            into `init`. It can be renamed/joined with other tables if more
    ///            information is desired.
    public func search(_ query: String) -> SearchRelation {
        let r = SearchRelation(index: self, query: query, scheme: searchRelationScheme)
        searchRelations.add(r)
        beginLoadIfNeeded()
        asyncUpdate(relation: r)
        return r
    }
}

extension RelationTextIndex {
    /// A Relation which holds search results from an index.
    /// The scheme is a single attribute: the contentIDAttribute which was
    /// passed in to the index. The Relation's contents update asynchronously
    /// when the search query is changed.
    public class SearchRelation: MemoryTableRelation {
        private let index: RelationTextIndex
        
        public var query: String {
            didSet {
                index.asyncUpdate(relation: self)
            }
        }
        
        init(index: RelationTextIndex, query: String, scheme: Scheme) {
            self.index = index
            self.query = query
            super.init(scheme: scheme)
        }
    }
}

extension RelationTextIndex {
    public static let matchStartCharacter: UnicodeScalar = "\u{2}"
    public static let matchEndCharacter: UnicodeScalar = "\u{3}"
    public static let ellipsesCharacter: UnicodeScalar = "\u{4}"
    
    static let specialCharacters: CharacterSet = {
        var s = CharacterSet()
        s.insert(matchStartCharacter)
        s.insert(matchEndCharacter)
        s.insert(ellipsesCharacter)
        return s
    }()
    
    /// A structured representation of a snippet. Initialize it with the raw string from a
    /// snippet column of a `SearchRelation`, and it will read the special characters embedded
    /// in the snippet string and transform them into this structured representation.
    public struct StructuredSnippet: Hashable {
        public var ellipsisAtStart: Bool
        public var ellipsisAtEnd: Bool
        
        public var string: String
        public var matches: [Range<String.Index>]
        
        public init(rawString: String) {
            var str = rawString
            
            if str.unicodeScalars.first == ellipsesCharacter {
                ellipsisAtStart = true
                str.remove(at: str.startIndex)
            } else {
                ellipsisAtStart = false
            }
            
            if str.unicodeScalars.last == ellipsesCharacter {
                ellipsisAtEnd = true
                str.remove(at: str.index(before: str.endIndex))
            } else {
                ellipsisAtEnd = false
            }
            
            let pieces = str.components(separatedBy: String(matchStartCharacter))
            if pieces.count == 0 {
                string = ""
                matches = []
            } else if pieces.count == 1 {
                string = str
                matches = []
            } else {
                string = pieces[0]
                matches = []
                for piece in pieces.dropFirst() {
                    let subPieces = piece.components(separatedBy: String(matchEndCharacter))
                    if subPieces.count == 2 {
                        let match = subPieces[0]
                        let rest = subPieces[1]
                        
                        let matchStart = string.endIndex
                        string.append(match)
                        let matchEnd = string.endIndex
                        string.append(rest)
                        
                        matches.append(matchStart ..< matchEnd)
                    } else {
                        // Something has gone horribly wrong and we're missing the match end.
                        // This should never happen. Handle it gracefully by ignoring any
                        // possible match this may indicate.
                        NSLog("Failed to locate ending match string in snippet piece %@", piece)
                        string.append(piece)
                    }
                }
            }
        }
        
        public static func ==(lhs: StructuredSnippet, rhs: StructuredSnippet) -> Bool {
            return lhs.ellipsisAtStart == rhs.ellipsisAtStart
                && lhs.ellipsisAtEnd == rhs.ellipsisAtEnd
                && lhs.string == rhs.string
                && lhs.matches == rhs.matches
        }
        
        public var hashValue: Int {
            var hash = DJBHash()
            hash.combine(ellipsisAtStart.hashValue)
            hash.combine(ellipsisAtEnd.hashValue)
            hash.combine(string.hashValue)
            
            // String.Index isn't Hashable and doesn't have any convenient way to extract a value.
            // We'll just punt on it. Hopefully the rest will be sufficiently unique.
            hash.combine(matches.count)
            
            return hash.value
        }
    }
}

extension RelationTextIndex {
    /// Configuration for a column of searchable text.
    public struct ColumnConfig {
        /// The attribute that the snippet will be stored under in the result rows.
        public var snippetAttribute: Attribute
        
        /// A function which extracts searchable text from a row.
        public var textExtractor: (Row) -> Result<String, RelationError>
        
        public init(snippetAttribute: Attribute, textExtractor: @escaping (Row) -> Result<String, RelationError>) {
            self.snippetAttribute = snippetAttribute
            self.textExtractor = textExtractor
        }
    }
}

private extension RelationTextIndex {
    /// Update the contents of a given search relation with the latest search results.
    ///
    /// - Parameters:
    ///   - relation: The Relation to update.
    func asyncUpdate(relation: SearchRelation) {
        log("starting asyncUpdate for \(relation.query)")
        
        AsyncManager.currentInstance.registerCustomAction(affectedRelations: [relation], {
            let escapedContentID = self.db.escapeIdentifier(self.contentIDAttribute.name)
            
            var query = ""
            var parameters: [RelationValue] = []
            
            query += "SELECT \(Attribute.pageID) as \(escapedContentID), rank(matchinfo(\(contentTable))) as rank"
            
            for (i, column) in self.columnConfigs.enumerated() {
                let escapedName = self.db.escapeIdentifier(column.snippetAttribute.name)
                query += ", snippet(\(contentTable), ?, ?, ?, ?) as \(escapedName)"
                parameters.append(.text(String(RelationTextIndex.matchStartCharacter)))
                parameters.append(.text(String(RelationTextIndex.matchEndCharacter)))
                parameters.append(.text(String(RelationTextIndex.ellipsesCharacter)))
                parameters.append(.integer(Int64(i)))
            }
            
            query += " FROM \(contentTable) JOIN \(pagesTable) ON \(contentTable).docid = \(pagesTable).rowid WHERE content MATCH ?"
            parameters.append(.text(relation.query))
            
            return self.db.executeQuery(query, parameters).map({ rows in
                return mapOk(rows, { $0 }).then({ rows -> Result<Void, RelationError> in
                    log("asyncUpdate for \(relation.query) got rows \(rows)")
                    let rows = Set(rows.lazy.map({ $0.renameAttributes([Attribute.pageID: self.contentIDAttribute]) }))
                    
                    let added = rows - relation.values.allValues
                    let removed = relation.values.allValues - rows
                    
                    removed.forEach(relation.delete)
                    
                    for row in added {
                        let result = relation.add(row)
                        if let err = result.err {
                            // This is impossible, but handle it in case that ever changes.
                            return .Err(err)
                        }
                    }
                    
                    log("completed asyncUpdate for \(relation.query)")
                    return .Ok(())
                })
            }).err
        })
    }
    
    /// Update all match Relations which currently exist.
    func asyncUpdateAll() {
        for r in searchRelations.objectEnumerator() {
            self.asyncUpdate(relation: r as! RelationTextIndex.SearchRelation)
        }
    }
    
    /// Set the strings for a given page ID.
    ///
    /// - Parameters:
    ///   - strings: The content strings to set. These must be in the same order as self.columnConfigs.
    ///   - pageID: The page ID for this content.
    /// - Returns: A Result containing nothing on success and an error on failure.
    func set(strings: [String], pageID: RelationValue) -> Result<Void, RelationError> {
        log("Setting \(strings) for \(pageID)")
        return db.executeQuery("INSERT OR REPLACE INTO \(pagesTable)(\(Attribute.pageID)) VALUES (?)", [pageID]).then({ rows in
            let array = Array(rows)
            if let error = array.first?.err {
                log("Error inserting page \(pageID): \(error)")
                return .Err(error)
            }
            
            precondition(array.isEmpty, "Unexpected results from INSERT OR REPLACE INTO statement: \(array)")
            
            let sanitizedStrings = strings.map({
                $0.components(separatedBy: RelationTextIndex.specialCharacters).joined()
            })
            
            let rowid = db.lastInsertRowID()
            let columns = (["docid"] + columnNames).joined(separator: ", ")
            let valuesPlaceholders = (0 ... strings.count).map({ _ in "?" }).joined(separator: ", ")
            let values = [.integer(rowid)] + sanitizedStrings.map(RelationValue.text)
            
            log("Inserting values into content table: \(values)")
            
            return db.executeQuery("INSERT INTO \(contentTable)(\(columns)) VALUES (\(valuesPlaceholders))", values).then({ rows in
                let array = Array(rows)
                if let error = array.first?.err {
                    log("Error inserting content for \(pageID): error")
                    return .Err(error)
                } else {
                    precondition(array.isEmpty, "Unexpected results from INSERT INTO statement: \(array)")
                    log("Setting content for \(pageID) succeeded")
                    self.asyncUpdateAll()
                    return .Ok(())
                }
            })
        })
    }
    
    /// Delete the string for a given page ID.
    ///
    /// - Parameters:
    ///   - string: The content string that was previously set. This must match what
    ///             was passed in to the `set()` method.
    ///   - pageID: The page ID for this content.
    /// - Returns: A Result containing nothing on success and an error on failure.
    func delete(strings: [String], pageID: RelationValue) -> Result<Void, RelationError> {
        log("Deleting \(strings) for \(pageID)")
        return db.executeQuery("SELECT rowid FROM \(pagesTable) WHERE \(Attribute.pageID) == ?", [pageID]).then({ rows in
            let array = Array(rows)
            if array.count != 1 {
                return .Err(Error.consistencyError("Got multiple pages with the same ID in pages table"))
            }
            switch array[0] {
            case .Ok(let row):
                let rowid = row["rowid"]
                log("Deleting from content table rowid \(rowid)")
                return db.executeQueryWithEmptyResults("DELETE FROM \(pagesTable) WHERE rowid = ?", [rowid])
                    .and(db.executeQueryWithEmptyResults("DELETE FROM \(contentTable) WHERE docid = ?", [rowid]))
                    .map({
                        self.asyncUpdateAll()
                    })
            case .Err(let err):
                return .Err(err)
            }
        })
    }
    
    func beginLoadIfNeeded() {
        if case .notLoaded = state {
            beginLoad()
        }
    }
    
    func beginLoad() {
        guard case .notLoaded = state else {
            fatalError("Illegal state transition, beginLoad called with state \(state)")
        }
        
        log("Beginning load")
        
        self.state = .loadingIDs
        idRelation.asyncAllRows({
            switch $0 {
            case .Ok(let rows):
                let ids = rows.map({ $0[self.idAttribute] })
                self.beginLoadContent(ids: Set(ids))
            case .Err(let err):
                self.handle(error: err)
            }
        })
    }
    
    func beginLoadContent(ids: Set<RelationValue>) {
        guard case .loadingIDs = state else {
            fatalError("Illegal state transition, beginLoadContent called with state \(state)")
        }
        
        log("Beginning content load")
        
        self.state = .loadingContent(idsToLoad: ids)
        
        self.observationRemover = contentRelation.addAsyncObserver(RelationTextIndexObserver(owner: self))
        
        loadOneContent()
    }
    
    func loadOneContent() {
        guard case .loadingContent(var ids) = state else {
            fatalError("loadOneContent called in wrong state \(state)")
        }
        
        if let id = ids.popFirst() {
            log("Loading content for \(id)")
            loadContent(id: id, completion: {
                log("Completed content load for \(id)")
                self.state = .loadingContent(idsToLoad: ids)
                self.loadOneContent()
            })
        } else {
            log("Completed all content loading")
            state = .loaded
        }
    }
    
    func loadContent(id: RelationValue, completion: @escaping () -> Void) {
        contentRelation.select(contentIDAttribute *== id).asyncAllRows({
            switch $0 {
            case .Ok(let rows) where rows.isEmpty:
                self.handle(error: "Failed to load content for id \(id)")
            case .Ok(let rows) where rows.count > 1:
                self.handle(error: "Got more than one row for id \(id)")
            case .Ok(let rows):
                log("loadContent \(rows)")
                if let strings = flatten(rows.first.map(self.contentText)) {
                    let result = self.set(strings: strings, pageID: id)
                    if let err = result.err {
                        self.handle(error: err)
                    }
                } else {
                    self.handle(error: "Could not get content text for id \(id)")
                }
            case .Err(let err):
                self.handle(error: err)
            }
            completion()
        })
    }
    
    func contentText(row: Row) -> [String]? {
        let result = mapOk(columnConfigs.map({ $0.textExtractor(row) }), { $0 })
        switch result {
        case .Ok(let string):
            return string
        case .Err(let error):
            handle(error: error)
            return nil
        }
    }
    
    func handle(error: RelationError) {
        handle(error: "\(error)")
    }
    
    func handle(error: String) {
        // TODO: you know, handle it
        fatalError(error)
    }
}

private class RelationTextIndexObserver: AsyncRelationChangeCoalescedObserver {
    weak var owner: RelationTextIndex?
    
    init(owner: RelationTextIndex) {
        self.owner = owner
    }
    
    func relationWillChange(_ relation: Relation) {
        // Do nothing
    }
    
    func relationDidChange(_ relation: Relation, result: Result<RowChange, RelationError>) {
        guard let owner = owner else { return }
        
        switch result {
        case .Ok(let changes):
            switch owner.state {
            case .notLoaded:
                fatalError("Observer method called with notLoaded state, this should never happen")
            case .loadingIDs:
                // Nothing to be done
                break
            case .loadingContent(var idsToLoad):
                let removedIDs = changes.removed.map({ $0[owner.contentIDAttribute] })
                idsToLoad.subtract(removedIDs)
                
                let addedIDs = changes.added.map({ $0[owner.contentIDAttribute] })
                idsToLoad.formUnion(addedIDs)
                
                owner.state = .loadingContent(idsToLoad: idsToLoad)
            case .loaded:
                log("did change:\n\(loggableChanges(changes))")
                for row in changes.removed {
                    if let strings = owner.contentText(row: row) {
                        let result = owner.delete(strings: strings, pageID: row[owner.contentIDAttribute])
                        if let err = result.err {
                            owner.handle(error: err)
                        }
                    }
                }
                for row in changes.added {
                    if let strings = owner.contentText(row: row) {
                        let result = owner.set(strings: strings, pageID: row[owner.contentIDAttribute])
                        if let err = result.err {
                            owner.handle(error: err)
                        }
                    }
                }
            }
        case .Err:
            // Do something? Or not?
            break
        }
    }

    private func loggableChanges(_ rows: RowChange) -> String {
        func fixup(row: Row) -> Row {
            var result = row
            for (attribute, value) in row {
                if let string = value.get() as String? {
                    if let lastIndex = string.firstIndex(of: "\n") ?? string.index(string.startIndex, offsetBy: 40, limitedBy: string.endIndex) {
                        result[attribute] = .text(string[..<lastIndex] + "…")
                    }
                }
            }
            return result
        }
        
        let addedLines = rows.added.map({ "    Added: \(fixup(row: $0))" })
        let removedLines = rows.removed.map({ "    Removed: \(fixup(row: $0))" })
        
        return (addedLines + removedLines).joined(separator: "\n")
    }
}

private extension Attribute {
    static let pageID: Attribute = "page_id"
}

private let pagesTable = "pages"
private let contentTable = "content"

/// The built in SQLite tokenizers aren't quite sufficiently Unicode-aware for
/// our needs. We create our own tokenizer using NSLinguisticTagger. This function
/// registers the custom tokenizer with SQLite.
///
/// - Parameter db: The SQLite database to register the tokenizer with.
/// - Returns: A Result containing nothing on success, or an error on failure.
private func setupTokenizer(db: SQLiteDatabase) -> Result<Void, RelationError> {
    let pointerSize = MemoryLayout.size(ofValue: modulePointer)
    var pointerData: [UInt8] = Array(repeating: 0, count: pointerSize)
    memcpy(&pointerData, &modulePointer, pointerSize)
    
    return db.executeQuery("SELECT fts3_tokenizer(?, ?)", [.text(tokenizerName), .blob(pointerData)], bindBlobsRaw: true).then({
        let rows = Array($0)
        precondition(rows.count == 1, "Unexpected result from SELECT fts3_tokenizer call: \(rows)")
        return .Ok(())
    })
}

/// The name of the custom NSLinguisticTagger-based tokenizer registered with SQLite.
private let tokenizerName = "cocoatokenizer"

private var modulePointer: UnsafePointer<sqlite3_tokenizer_module> = {
    let ptr = UnsafeMutablePointer<sqlite3_tokenizer_module>.allocate(capacity: 1)
    
    ptr.pointee.iVersion = 0
    ptr.pointee.xCreate = xCreate
    ptr.pointee.xDestroy = xDestroy
    ptr.pointee.xOpen = xOpen
    ptr.pointee.xClose = xClose
    ptr.pointee.xNext = xNext
    
    return UnsafePointer(ptr)
}()

private struct Cursor {
    var sqliteCursor: sqlite3_tokenizer_cursor
    var tokens: [(data: NSData, offset: (Int32, Int32))]
    var currentIndex: Int
}

private struct IntermediateToken: Hashable, Comparable {
    var string: String
    var range: NSRange
    
    static func ==(lhs: IntermediateToken, rhs: IntermediateToken) -> Bool {
        return lhs.string == rhs.string
            && lhs.range.location == rhs.range.location
            && lhs.range.length == rhs.range.length
    }
    
    static func <(lhs: IntermediateToken, rhs: IntermediateToken) -> Bool {
        if lhs.range.location < rhs.range.location {
            return true
        } else if lhs.range.location > rhs.range.location {
            return false
        }
        
        if lhs.range.location < rhs.range.location {
            return true
        } else if lhs.range.location > rhs.range.location {
            return false
        }
        
        return false
    }
    
    var hashValue: Int {
        var hash = DJBHash()
        hash.combine(string.hashValue)
        hash.combine(range.location)
        hash.combine(range.length)
        return hash.value
    }
}

private func xCreate(argc: Int32, argv: UnsafePointer<UnsafePointer<Int8>?>?, outTokenizer: UnsafeMutablePointer<UnsafeMutablePointer<sqlite3_tokenizer>?>?) -> Int32 {
    let ptr = UnsafeMutablePointer<sqlite3_tokenizer>.allocate(capacity: 1)
    ptr.pointee.pModule = modulePointer
    outTokenizer?.pointee = ptr
    
    return SQLITE_OK
}

private func xDestroy(tokenizer: UnsafeMutablePointer<sqlite3_tokenizer>?) -> Int32 {
    tokenizer?.deallocate()
    return SQLITE_OK
}

private func xOpen(tokenizer: UnsafeMutablePointer<sqlite3_tokenizer>?, input: UnsafePointer<Int8>?, nBytes: Int32, outCursor: UnsafeMutablePointer<UnsafeMutablePointer<sqlite3_tokenizer_cursor>?>?) -> Int32 {
    let inputLength: Int
    if nBytes >= 0 {
        inputLength = Int(nBytes)
    } else {
        if let input = input {
            inputLength = Int(strlen(input))
        } else {
            inputLength = 0
        }
    }
    let maybeString: String? = input?.withMemoryRebound(to: UInt8.self, capacity: inputLength, {
        let buffer = UnsafeBufferPointer(start: $0, count: inputLength)
        return String(bytes: buffer, encoding: .utf8)
    })
    
    guard let string = maybeString else {
        return SQLITE_NOMEM
    }
    
    let nsstring = string as NSString
    let range = NSRange(location: 0, length: nsstring.length)
    
    var tokens: Set<IntermediateToken> = []
    
    // We don't want multiple tokens for the same area of text.
    // This tracks which regions are covered and which are not.
    // If multiple tokens are generated for the same area, subsequent
    // ones are ignored.
    let coveredIndices = NSMutableIndexSet()
    func check(range: NSRange) -> Bool {
        if coveredIndices.intersects(in: range) {
            return false
        } else {
            coveredIndices.add(in: range)
            return true
        }
    }
    
    func fold(_ string: String) -> String {
        // NOTE: needs to be consistent, so we're not using a locale here.
        // If we want to use a locale, then we'll need to fetch it once and remember it.
        return string.lowercased()
    }
    
    let tagger = NSLinguisticTagger(tagSchemes: [NSLinguisticTagScheme.tokenType], options: 0)
    tagger.string = string

    // Consider reinstating this in some distant future when we figure out how to make stemming work
//    tagger.enumerateTags(in: range,
//                         scheme: NSLinguisticTagSchemeLemma,
//                         options: [.omitWhitespace, .omitPunctuation, .omitOther],
//                         using: {
//        tag, tokenRange, sentenceRange, stop in
//        guard check(range: tokenRange) else { return }
//        let string = tag.isEmpty ? nsstring.substring(with: tokenRange) : tag
//        tokens.insert(IntermediateToken(string: fold(string), range: tokenRange))
//    })
    
    tagger.enumerateTags(in: range,
                         scheme: NSLinguisticTagScheme.tokenType,
                         options: [.omitWhitespace, .omitPunctuation, .omitOther],
                         using: {
        tag, tokenRange, sentenceRange, stop in
        guard check(range: tokenRange) else { return }
        tokens.insert(IntermediateToken(string: fold(nsstring.substring(with: tokenRange)), range: tokenRange))
    })
    
    func location16ToLocation8(_ location: Int) -> Int32 {
        let index16 = string.utf16.index(string.utf16.startIndex, offsetBy: location)
        // TODO: can this fail? If yes, what do?
        let index8 = index16.samePosition(in: string.utf8)!
        return Int32(string.utf8.distance(from: string.utf8.startIndex, to: index8))
    }
    
    let convertedTokens: [(data: NSData, offset: (Int32, Int32))] = tokens.sorted().map({
        let data = $0.string.data(using: .utf8)! as NSData
        let start = location16ToLocation8($0.range.location)
        let end = location16ToLocation8(NSMaxRange($0.range))
        return (data, (start, end))
    })
    
    let ptr = UnsafeMutablePointer<Cursor>.allocate(capacity: 1)
    ptr.initialize(to:
        Cursor(sqliteCursor: sqlite3_tokenizer_cursor(pTokenizer: tokenizer),
               tokens: convertedTokens,
               currentIndex: 0))
    
    ptr.withMemoryRebound(to: sqlite3_tokenizer_cursor.self, capacity: 1, {
        outCursor?.pointee = $0
    })
    
    return SQLITE_OK
}

private func xClose(cursor: UnsafeMutablePointer<sqlite3_tokenizer_cursor>?) -> Int32 {
    cursor?.withMemoryRebound(to: Cursor.self, capacity: 1, {
        $0.deinitialize(count: 1)
        $0.deallocate()
    })
    return SQLITE_OK
}

private func xNext(cursor: UnsafeMutablePointer<sqlite3_tokenizer_cursor>?, outToken: UnsafeMutablePointer<UnsafePointer<Int8>?>?, outNBytes: UnsafeMutablePointer<Int32>?, outStartOffset: UnsafeMutablePointer<Int32>?, outEndOffset: UnsafeMutablePointer<Int32>?, outPosition: UnsafeMutablePointer<Int32>?) -> Int32 {
    guard let cursor = cursor else { return SQLITE_NOMEM }
    
    return cursor.withMemoryRebound(to: Cursor.self, capacity: 1, { ptr in
        let i = ptr.pointee.currentIndex
        if i >= ptr.pointee.tokens.count {
            return SQLITE_DONE
        }
        
        let token = ptr.pointee.tokens[i]
        outToken?.pointee = token.data.bytes.assumingMemoryBound(to: Int8.self)
        outNBytes?.pointee = Int32(token.data.length)
        outStartOffset?.pointee = token.offset.0
        outEndOffset?.pointee = token.offset.1
        outPosition?.pointee = Int32(i)
        
        ptr.pointee.currentIndex = i + 1
        
        return SQLITE_OK
    })
}

/// Compute a rank rating for a search based on matchinfo data.
/// Borrowed from https://www.sqlite.org/fts3.html#appendix_a
private func rank(context: OpaquePointer?, nVal: Int32, args: UnsafeMutablePointer<OpaquePointer?>?) {
    guard nVal == 1 else {
        sqlite3_result_error(context, "Wrong number of arguments to function rank()", -1)
        return
    }
    
    let matchInfo = sqlite3_value_blob(args![0]).assumingMemoryBound(to: Int32.self)
    let nPhrase = Int(matchInfo[0])
    let nCol = Int(matchInfo[1])
    
    var score = 0.0
    
    for iPhrase in 0 ..< nPhrase {
        let phraseInfo = matchInfo + 2 + iPhrase * nCol * 3
        for iCol in 0 ..< nCol {
            let hitCount = phraseInfo[3 * iCol]
            let globalHitCount = phraseInfo[3 * iCol + 1]
            
            // TODO: allow specifying different weights for different columns?
            let weight = 1.0
            
            score += Double(hitCount) / Double(globalHitCount) * weight
        }
    }
    
    sqlite3_result_double(context, score)
}

/// A simple debug logging function. Uncomment the print to see logs from this class.
///
/// - Parameter string: The string to log.
private func log(_ string: @autoclosure () -> String) {
//    print(string())
}
