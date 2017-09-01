//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import XCTest

import PLRelational


class RelationTextIndexTests: XCTestCase {
    func testStuff() {
        let testData = [
            ("2477DFB5-FC3C-4191-B64B-B92270D653D8", "我的气垫船装满了鳝鱼."),
            ("DAFCEDEB-7471-4A36-922F-CB3FCDE3A73E", "I am a pretty princess."),
            ("FD06B7EE-B10E-47BE-BEF6-BE94A025B11A", "Let me tell you a story. A story of adventure and woe. A story of sacrifice and redemption. A story of legend. Once upon a time there was a princess. In the forest, she ate some ham. Then she took a nap. When she awoke, she had been eaten by a ferocious bear. This made her rather sad."),
            ("E35CA82E-4823-4F23-9B7A-561CAF250DD6", "I gave my love a chicken. It had no bone."),
            ("843235CD-EAC6-4A0D-9C5D-CAD28F077414", "For more information about princesses, consult your local librarian."),
            ("6E15A045-A870-491C-B3DE-ACC6E360FFF8", "FOR MORE INFORMATION ABOUT PRINCESSES, CONSULT YOUR LOCAL LIBRARIAN.")
        ]
        
        let content = MemoryTableRelation(scheme: ["id", "text"])
        for (id, text) in testData {
            XCTAssertNil(content.add(["id": id, "text": text]).err)
        }
        
        let ids = MemoryTableRelation(scheme: ["id"])
        for (id, _) in testData {
            XCTAssertNil(ids.add(["id": id]).err)
        }
        
        let columnConfig = RelationTextIndex.ColumnConfig(snippetAttribute: "snippet", textExtractor: { (row: Row) in .Ok(row["text"].get()!) })
        let r = try! RelationTextIndex(ids: (ids, "id"), content: (content, "id"), columnConfigs: [columnConfig])
        
        let princess = r.search("princess*")
        let hovercraft = r.search("气垫船")
        
        var princessExpected: Set<Row> = [
            ["id": "DAFCEDEB-7471-4A36-922F-CB3FCDE3A73E",
             "snippet": "I am a pretty \u{2}princess\u{3}."],
            ["id": "FD06B7EE-B10E-47BE-BEF6-BE94A025B11A",
             "snippet": "\u{4}Once upon a time there was a \u{2}princess\u{3}. In the forest, she ate some ham\u{4}"],
            ["id": "843235CD-EAC6-4A0D-9C5D-CAD28F077414",
             "snippet": "For more information about \u{2}princesses\u{3}, consult your local librarian."],
            ["id": "6E15A045-A870-491C-B3DE-ACC6E360FFF8",
             "snippet": "FOR MORE INFORMATION ABOUT \u{2}PRINCESSES\u{3}, CONSULT YOUR LOCAL LIBRARIAN."]
        ]
        let hovercraftExpected: Set<Row> = [
            ["id": "2477DFB5-FC3C-4191-B64B-B92270D653D8",
             "snippet": "我的\u{2}气垫\u{3}\u{2}船\u{3}装满了鳝鱼."]
        ]
        let group = DispatchGroup()
        
        group.enter()
        var princessRows: Set<Row> = []
        var princessDone = false
        let princessObserver = Observer(callback: {
            princessRows = $0
            if $0 == princessExpected && !princessDone {
                princessDone = true
                group.leave()
            }
        })
        let princessRemover = princess.project(dropping: ["rank"]).addAsyncObserver(princessObserver)
        
        group.enter()
        var hovercraftRows: Set<Row> = []
        var hovercraftDone = false
        let hovercraftObserver = Observer(callback: {
            hovercraftRows = $0
            if $0 == hovercraftExpected && !hovercraftDone {
                hovercraftDone = true
                group.leave()
            }
        })
        let hovercraftRemover = hovercraft.project(dropping: ["rank"]).addAsyncObserver(hovercraftObserver)
        
        group.notify(queue: .main, execute: { CFRunLoopStop(CFRunLoopGetCurrent()) })
        CFRunLoopRunOrFail()
        
        XCTAssertEqual(princessRows, princessExpected)
        XCTAssertEqual(hovercraftRows, hovercraftExpected)
        
        AssertStructuredSnippets(rows: princessRows, attribute: "snippet", snippets:
            (false, false, "I am a pretty princess.", [14 ..< 22]),
            (true, true, "Once upon a time there was a princess. In the forest, she ate some ham", [29 ..< 37]),
            (false, false, "For more information about princesses, consult your local librarian.", [27 ..< 37]),
            (false, false, "FOR MORE INFORMATION ABOUT PRINCESSES, CONSULT YOUR LOCAL LIBRARIAN.", [27 ..< 37])
        )
        AssertStructuredSnippets(rows: hovercraftRows, attribute: "snippet", snippets:
            (false, false, "我的气垫船装满了鳝鱼.", [2 ..< 4, 4 ..< 5])
        )
        
        group.enter()
        princess.query = "librarian"
        princessExpected = [
            ["id": "843235CD-EAC6-4A0D-9C5D-CAD28F077414",
             "snippet": "For more information about princesses, consult your local \u{2}librarian\u{3}."],
            ["id": "6E15A045-A870-491C-B3DE-ACC6E360FFF8",
             "snippet": "FOR MORE INFORMATION ABOUT PRINCESSES, CONSULT YOUR LOCAL \u{2}LIBRARIAN\u{3}."]
        ]
        princessDone = false
        
        group.notify(queue: .main, execute: { CFRunLoopStop(CFRunLoopGetCurrent()) })
        CFRunLoopRunOrFail()
        
        XCTAssertEqual(princessRows, princessExpected)
        XCTAssertEqual(hovercraftRows, hovercraftExpected)
        
        AssertStructuredSnippets(rows: princessRows, attribute: "snippet", snippets:
            (false, false, "For more information about princesses, consult your local librarian.", [58 ..< 67]),
            (false, false, "FOR MORE INFORMATION ABOUT PRINCESSES, CONSULT YOUR LOCAL LIBRARIAN.", [58 ..< 67])
        )
        
        princessRemover()
        hovercraftRemover()
    }
    
    func testMultiSnippets() {
        let testData = [
            (1, "There once was a pretty princess.", "CHAPTER 1: PRINCESS"),
            (2, "She ate a strange mushroom and died.", "CHAPTER 2: THE PRINCESS DIES"),
            (3, "The End.", "CHAPTER 3: THE END")
        ]
        
        let content = MemoryTableRelation(scheme: ["id", "text", "title"])
        for (id, text, title) in testData {
            XCTAssertNil(content.add(["id": Int64(id), "text": text, "title": title]).err)
        }
        
        let ids = content.project(["id"])
        
        let textConfig = RelationTextIndex.ColumnConfig(snippetAttribute: "text_snippet", textExtractor: {
            return .Ok($0["text"].get()!)
        })
        let titleConfig = RelationTextIndex.ColumnConfig(snippetAttribute: "title_snippet", textExtractor: {
            return .Ok($0["title"].get()!)
        })
        
        let r = try! RelationTextIndex(ids: (ids, "id"), content: (content, "id"), columnConfigs: [textConfig, titleConfig])
        
        let princess = r.search("princess")
        
        let princessExpected: Set<Row> = [
            ["id": 1, "text_snippet": "There once was a pretty \u{2}princess\u{3}.", "title_snippet": "CHAPTER 1: \u{2}PRINCESS\u{3}"],
            ["id": 2, "text_snippet": "She ate a strange mushroom and died.", "title_snippet": "CHAPTER 2: THE \u{2}PRINCESS\u{3} DIES"],
        ]
        
        let group = DispatchGroup()
        
        group.enter()
        var princessRows: Set<Row> = []
        var princessDone = false
        let princessObserver = Observer(callback: {
            princessRows = $0
            if $0 == princessExpected && !princessDone {
                princessDone = true
                group.leave()
            }
        })
        let princessRemover = princess.project(dropping: ["rank"]).addAsyncObserver(princessObserver)
        
        group.notify(queue: .main, execute: { CFRunLoopStop(CFRunLoopGetCurrent()) })
        CFRunLoopRunOrFail()
        
        XCTAssertEqual(princessRows, princessExpected)
        AssertStructuredSnippets(rows: princessRows, attribute: "text_snippet", snippets:
            (false, false, "There once was a pretty princess.", [24 ..< 32]),
            (false, false, "She ate a strange mushroom and died.", [])
        )
        AssertStructuredSnippets(rows: princessRows, attribute: "title_snippet", snippets:
            (false, false, "CHAPTER 1: PRINCESS", [11 ..< 19]),
            (false, false, "CHAPTER 2: THE PRINCESS DIES", [15 ..< 23])
        )
        princessRemover()
    }
    
    func testCaseInsensitivity() {
        AssertMatches("princess",
                      (true, "I am a pretty princess"),
                      (false, "I am a pretty prince"),
                      (true, "I am a pretty PRINCESS"),
                      (true, "I am a pretty prINCess"))
        AssertMatches("PRINCESS",
                      (true, "I am a pretty princess"),
                      (false, "I am a pretty prince"),
                      (true, "I am a pretty PRINCESS"),
                      (true, "I am a pretty prINCess"))
        AssertMatches("I am a pretty PRINCESS",
                      (true, "I am a pretty princess"),
                      (false, "I am a pretty prince"),
                      (true, "I am a pretty PRINCESS"),
                      (true, "I am a pretty prINCess"))
        AssertMatches("prinCESs",
                      (true, "I am a pretty princess"),
                      (false, "I am a pretty prince"),
                      (true, "I am a pretty PRINCESS"),
                      (true, "I am a pretty prINCess"))
    }
    
    func testSearchStemming() {
        AssertMatches("starts",
                      (true, "It All Starts Here"),
                      (true, "it all starts here"),
                      (false, "It All Ends Here"))
    }
    
    func testContentChanges() {
        let content = MemoryTableRelation(scheme: ["id", "text"])
        let ids = content.project(["id"])
        
        let columnConfig = RelationTextIndex.ColumnConfig(snippetAttribute: "snippet", textExtractor: { (row: Row) in .Ok(row["text"].get()!) })
        let r = try! RelationTextIndex(ids: (ids, "id"), content: (content, "id"), columnConfigs: [columnConfig])
        
        let princess = r.search("princess*")
        let hovercraft = r.search("hovercraft")
        
        var princessExpected: Set<Row> = []
        var hovercraftExpected: Set<Row> = []
        let group = DispatchGroup()
        
        var princessRows: Set<Row> = []
        var princessDone = false
        let princessObserver = Observer(callback: {
            princessRows = $0
            if $0 == princessExpected && !princessDone {
                princessDone = true
                group.leave()
            }
        })
        let princessRemover = princess.project("id").addAsyncObserver(princessObserver)
        
        var hovercraftRows: Set<Row> = []
        var hovercraftDone = false
        let hovercraftObserver = Observer(callback: {
            hovercraftRows = $0
            if $0 == hovercraftExpected && !hovercraftDone {
                hovercraftDone = true
                group.leave()
            }
        })
        let hovercraftRemover = hovercraft.project("id").addAsyncObserver(hovercraftObserver)
        
        func test(change: (Void) -> Void, princess: Set<Row>, hovercraft: Set<Row>, line: UInt = #line) {
            NSLog("%@", "Test \(line)")
            princessExpected = princess
            hovercraftExpected = hovercraft
            princessDone = false
            hovercraftDone = false
            group.enter()
            group.enter()
            
            change()
            
            group.notify(queue: .main, execute: { CFRunLoopStop(CFRunLoopGetCurrent()) })
            CFRunLoopRunOrFail(line: line)
            
            XCTAssertEqual(princessRows, princessExpected, line: line)
            XCTAssertEqual(hovercraftRows, hovercraftExpected, line: line)
        }
        
        test(change: {
            content.asyncAdd(["id": 101, "text": "The pretty princess robbed a bank."])
        }, princess: [["id": 101]], hovercraft: [])
        
        test(change: {
            content.asyncUpdate(Attribute("id") *== 101, newValues: ["text": "The handsome prince drove the getaway hovercraft."])
        }, princess: [], hovercraft: [["id": 101]])
        
        test(change: {
            content.asyncAdd(["id": 102, "text": "It's just a bunch of stuff that happened"])
        }, princess: [], hovercraft: [["id": 101]])
        
        test(change: {
            content.asyncAdd(["id": 103, "text": "Would you stop talking about princesses all the time please?"])
        }, princess: [["id": 103]], hovercraft: [["id": 101]])
        
        test(change: {
            content.asyncUpdate(Attribute("id") *== 103, newValues: ["text": "We just love talking about princesses all the time."])
        }, princess: [["id": 103]], hovercraft: [["id": 101]])
        
        princessRemover()
        hovercraftRemover()
    }
    
    func testContentChangesWithExtraColumns() {
        let content = MemoryTableRelation(scheme: ["id", "text", "unrelated"])
        let ids = content.project(["id"])
        
        let columnConfig = RelationTextIndex.ColumnConfig(snippetAttribute: "snippet", textExtractor: { (row: Row) in .Ok(row["text"].get()!) })
        let r = try! RelationTextIndex(ids: (ids, "id"), content: (content, "id"), columnConfigs: [columnConfig])
        
        let princess = r.search("princess*")
        let hovercraft = r.search("hovercraft")
        
        var princessExpected: Set<Row> = []
        var hovercraftExpected: Set<Row> = []
        let group = DispatchGroup()
        
        var princessRows: Set<Row> = []
        var princessDone = false
        let princessObserver = Observer(callback: {
            princessRows = $0
            if $0 == princessExpected && !princessDone {
                princessDone = true
                group.leave()
            }
        })
        let princessRemover = princess.project("id").addAsyncObserver(princessObserver)
        
        var hovercraftRows: Set<Row> = []
        var hovercraftDone = false
        let hovercraftObserver = Observer(callback: {
            hovercraftRows = $0
            if $0 == hovercraftExpected && !hovercraftDone {
                hovercraftDone = true
                group.leave()
            }
        })
        let hovercraftRemover = hovercraft.project("id").addAsyncObserver(hovercraftObserver)
        
        func test(change: (Void) -> Void, princess: Set<Row>, hovercraft: Set<Row>, line: UInt = #line) {
            NSLog("%@", "Test \(line)")
            princessExpected = princess
            hovercraftExpected = hovercraft
            princessDone = false
            hovercraftDone = false
            group.enter()
            group.enter()
            
            change()
            
            group.notify(queue: .main, execute: { CFRunLoopStop(CFRunLoopGetCurrent()) })
            CFRunLoopRunOrFail(line: line)
            
            XCTAssertEqual(princessRows, princessExpected, line: line)
            XCTAssertEqual(hovercraftRows, hovercraftExpected, line: line)
        }
        
        test(change: {
            content.asyncAdd(["id": 101, "text": "The pretty princess robbed a bank.", "unrelated": 1])
        }, princess: [["id": 101]], hovercraft: [])
        
        test(change: {
            content.asyncUpdate(Attribute("id") *== 101, newValues: ["text": "The handsome prince drove the getaway hovercraft."])
        }, princess: [], hovercraft: [["id": 101]])
        
        test(change: {
            content.asyncAdd(["id": 102, "text": "It's just a bunch of stuff that happened", "unrelated": 2])
        }, princess: [], hovercraft: [["id": 101]])
        
        test(change: {
            content.asyncAdd(["id": 103, "text": "Would you stop talking about princesses all the time please?", "unrelated": 3])
        }, princess: [["id": 103]], hovercraft: [["id": 101]])
        
        test(change: {
            content.asyncUpdate(Attribute("id") *== 103, newValues: ["text": "We just love talking about princesses all the time."])
        }, princess: [["id": 103]], hovercraft: [["id": 101]])
        
        test(change: {
            content.asyncUpdate(Attribute("id") *== 101, newValues: ["unrelated": 42])
        }, princess: [["id": 103]], hovercraft: [["id": 101]])

        princessRemover()
        hovercraftRemover()
    }
    
    func testDiacritics() {
        let testCases = [
            ("aviṣādaḥ", "nirbhayaḥ निर्भयः 無怖 'jigs pa med pa འཇིགས་པ་མེད་པ་\naviṣādaḥ अविषादः 無退縮 無縮 zhum pa med pa ཞུམ་པ་མེད་པ་\nna uttrasati न उत्त्रसति 不怕 不嚇 mi skrag མི་སྐྲག་"),
            ("pārśvaḥ", "pārśvaḥ पार्श्वः 脇肩 rtsib logs རྩིབ་ལོགས་\nkaṭiḥ कटिः 小便 rked pa རྐེད་པ་\nbuliḥ बुलिः 肛門 rkub རྐུབ་"),
            ("pratīkṣate", "upajagāma उपजगाम 近去 nye bar song ཉེ་བར་སོང་\nabhimukham upagatam (amukham upagatam) अभिमुखमुपगतम् (अमुखमुपगतम्) 現前近去 mngon du nye bar song མངོན་དུ་ཉེ་བར་སོང་\npratīkṣate प्रतीक्षते 坐 sdod སྡོད་"),
            ("viśiṣṭaḥ", "atyudgataḥ अत्युद्गतः 高出 zang yag / zangs yag ཟང་ཡག་\nviśiṣṭaḥ विशिष्टः 最妙 brtan yas བརྟན་ཡས་\nnevalaḥ नेवलः 泥羅婆 stobs yas སྟོབས་ཡས་"),
            ("déjeuner", "J'ai éliminé le déjeuner."),
            ("ça", "Comme ci comme ça."),
            ("El niño", "This year's el niño will likely result in the end of the world."),
        ]
        
        let content = MemoryTableRelation(scheme: ["id", "text"])
        let ids = content.project(["id"])
        
        let columnConfig = RelationTextIndex.ColumnConfig(snippetAttribute: "snippet", textExtractor: { (row: Row) in .Ok(row["text"].get()!) })
        let r = try! RelationTextIndex(ids: (ids, "id"), content: (content, "id"), columnConfigs: [columnConfig])
        
        var searchRelations: [(String, Relation)] = []
        
        for (index, (searchTerm, text)) in testCases.enumerated() {
            searchRelations.append((text, r.search(searchTerm).join(content).project("text")))
            content.asyncAdd(["id": Int64(index), "text": text])
        }
        
        let group = DispatchGroup()
        
        var removers: [AsyncManager.ObservationRemover] = []
        
        for (expected, searchRelation) in searchRelations {
            group.enter()
            var done = false
            let remover = searchRelation.addAsyncObserver(Observer(callback: {
                if !done && $0 == [["text": expected]] {
                    done = true
                    group.leave()
                }
            }))
            removers.append(remover)
        }
        
        group.notify(queue: .main, execute: { CFRunLoopStop(CFRunLoopGetCurrent()) })
        CFRunLoopRunOrFail()
        
        for (expected, searchRelation) in searchRelations {
            AssertEqual(searchRelation, MakeRelation(["text"], [.text(expected)]))
        }
        
        for remover in removers {
            remover()
        }
    }
}

private class Observer: AsyncRelationContentCoalescedObserver {
    let callback: (Set<Row>) -> Void
    
    init(callback: @escaping (Set<Row>) -> Void) {
        self.callback = callback
    }
    
    func relationWillChange(_ relation: Relation) {}
    
    func relationDidChange(_ relation: Relation, result: Result<Set<Row>, RelationError>) {
        if let rows = result.ok {
            callback(rows)
        }
    }
}

private func AssertMatches(_ query: String, file: StaticString = #file, line: UInt = #line, _ items: (Bool, String)...) {
    let content = MemoryTableRelation(scheme: ["id", "include", "text"])
    for (index, (include, text)) in items.enumerated() {
        XCTAssertNil(content.add(["id": Int64(index), "include": RelationValue.boolValue(include), "text": text]).err, file: file, line: line)
    }
    
    let ids = content.project(["id"])
    
    let textConfig = RelationTextIndex.ColumnConfig(snippetAttribute: "text_snippet", textExtractor: {
        return .Ok($0["text"].get()!)
    })
    
    let r = try! RelationTextIndex(ids: (ids, "id"), content: (content, "id"), columnConfigs: [textConfig])
    
    let search = r.search(query)
    
    let expected = content.select(Attribute("include"))
    
    let group = DispatchGroup()
    
    group.enter()
    var done = false
    let observer = Observer(callback: {
        let expectedIDs = Set(expected.project("id").rows().flatMap({ $0.ok }))
        let actualIDs = Set($0.map({ $0.rowWithAttributes(["id"]) }))
        if actualIDs == expectedIDs && !done {
            done = true
            group.leave()
        }
    })
    let remover = search.addAsyncObserver(observer)
    
    group.notify(queue: .main, execute: { CFRunLoopStop(CFRunLoopGetCurrent()) })
    CFRunLoopRunOrFail(file: file, line: line)
    
    AssertEqual(expected, search.project("id").join(content), file: file, line: line)
    remover()
}

private func AssertStructuredSnippets(rows: Set<Row>, attribute: Attribute, file: StaticString = #file, line: UInt = #line, snippets: (Bool, Bool, String, [Range<Int>])...) {
    let strings = rows.map({ $0[attribute].get()! as String })
    let rowSnippets = strings.map(RelationTextIndex.StructuredSnippet.init)
    let passedInSnippets: [RelationTextIndex.StructuredSnippet] = snippets.map({ ellipsisAtStart, ellipsisAtEnd, string, matches in
        let resolvedMatches: [Range<String.Index>] = matches.map({
            let start = string.index(string.startIndex, offsetBy: $0.lowerBound)
            let end = string.index(string.startIndex, offsetBy: $0.upperBound)
            return start ..< end
        })
        var snippet = RelationTextIndex.StructuredSnippet(rawString: "")
        snippet.ellipsisAtStart = ellipsisAtStart
        snippet.ellipsisAtEnd = ellipsisAtEnd
        snippet.string = string
        snippet.matches = resolvedMatches
        return snippet
    })
    XCTAssertEqual(Set(rowSnippets), Set(passedInSnippets), file: file, line: line)
}
