//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

@testable import PLRelational
import XCTest


class BookmarkableGraphTests: XCTestCase {
    func testPaths() {
        let graph = BookmarkableGraph<Int>()
        
        let start = graph.addEmptyNode()
        XCTAssertEqual(graph.computePath(from: start, to: start), [])
        
        let next = graph.addNode(fromBookmark: start, outboundData: 1, inboundData: -1)
        XCTAssertEqual(graph.computePath(from: start, to: next), [1])
        XCTAssertEqual(graph.computePath(from: next, to: start), [-1])
        
        let next2 = graph.addNode(fromBookmark: next, outboundData: 2, inboundData: -2)
        XCTAssertEqual(graph.computePath(from: start, to: next2), [1, 2])
        XCTAssertEqual(graph.computePath(from: next2, to: start), [-2, -1])
        XCTAssertEqual(graph.computePath(from: next, to: next2), [2])
        XCTAssertEqual(graph.computePath(from: next2, to: next), [-2])
    }
    
    func testGarbageCollection() {
        let graph = BookmarkableGraph<Void>()
        
        let start = graph.addEmptyNode()
        
        weak var node1: AnyObject?
        weak var node2: AnyObject?
        weak var node3: AnyObject?
        weak var node4: AnyObject?
        weak var node5: AnyObject?
        
        do {
            let next1 = graph.addNode(fromBookmark: start, outboundData: (), inboundData: ())
            node1 = graph.nodeForBookmarkForTesting(next1)
            
            let next2 = graph.addNode(fromBookmark: start, outboundData: (), inboundData: ())
            node2 = graph.nodeForBookmarkForTesting(next2)
            
            let next3 = graph.addNode(fromBookmark: start, outboundData: (), inboundData: ())
            node3 = graph.nodeForBookmarkForTesting(next3)
            
            let next4 = graph.addNode(fromBookmark: start, outboundData: (), inboundData: ())
            node4 = graph.nodeForBookmarkForTesting(next4)
            
            let next5 = graph.addNode(fromBookmark: start, outboundData: (), inboundData: ())
            node5 = graph.nodeForBookmarkForTesting(next5)
        }
        
        XCTAssertNil(node1)
        XCTAssertNil(node2)
        XCTAssertNil(node3)
        XCTAssertNil(node4)
        XCTAssertNil(node5)
    }
}
