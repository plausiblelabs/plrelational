//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//


class BookmarkableGraph<EdgeData> {
    typealias Bookmark = BookmarkableGraphBookmark<EdgeData>
    
    func addEmptyNode() -> Bookmark {
        return Bookmark(graph: self, node: Node())
    }
    
    func addNode(fromBookmark: Bookmark, outboundData: EdgeData, inboundData: EdgeData) -> Bookmark {
        let newNode = Node()
        fromBookmark.node.edges.append((newNode, outboundData))
        newNode.edges.append((fromBookmark.node, inboundData))
        return Bookmark(graph: self, node: newNode)
    }
    
    func computePath(from: Bookmark, to: Bookmark) -> [EdgeData] {
        if from.node === to.node {
            return []
        }
        
        typealias SearchEntry = (node: Node, from: Node?, soFar: [EdgeData])
        
        var toSearch: ArraySlice<SearchEntry> = [(node: from.node, from: nil, soFar: [])]
        while let entry = toSearch.first {
            toSearch = toSearch.dropFirst()
            
            for edge in entry.node.edges {
                if edge.node === to.node {
                    return entry.soFar + [edge.data]
                } else if edge.node === entry.from {
                    // Do nothing, we don't want to backtrack.
                } else {
                    toSearch.append((node: edge.node, from: entry.node, soFar: entry.soFar + [edge.data]))
                }
            }
        }
        
        fatalError("Could not compute a path from \(from) to \(to)")
    }
}


fileprivate extension BookmarkableGraph {
    typealias Node = BookmarkableGraphNode<EdgeData>
    
    func remove(bookmark: Bookmark) {
        bookmark.node.hasBookmark = false
        
        var node = bookmark.node
        while !node.hasBookmark && node.edges.count == 1 {
            removeInboundEdges(node: node)
            node = node.edges[0].node
        }
    }
    
    private func removeInboundEdges(node: Node) {
        for edge in node.edges {
            edge.node.edges.removeOne({ $0.node === node })
        }
    }
}

extension BookmarkableGraph {
    func nodeForBookmarkForTesting(_ bookmark: Bookmark) -> AnyObject {
        return bookmark.node
    }
}

class BookmarkableGraphBookmark<EdgeData> {
    let graph: BookmarkableGraph<EdgeData>
    fileprivate let node: BookmarkableGraphNode<EdgeData>
    
    fileprivate init(graph: BookmarkableGraph<EdgeData>, node: BookmarkableGraphNode<EdgeData>) {
        self.graph = graph
        self.node = node
    }
    
    deinit {
        graph.remove(bookmark: self)
    }
}

private class BookmarkableGraphNode<EdgeData> {
    var edges: [(node: BookmarkableGraphNode<EdgeData>, data: EdgeData)] = []
    var hasBookmark: Bool = true
}
