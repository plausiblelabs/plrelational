//
// Copyright (c) 2017 Plausible Labs Cooperative, Inc.
// All rights reserved.
//


/// A class that represents a specialized graph. It's really a tree, but
/// with no concept of a root, so "graph" seemed to fit better. Clients
/// interact with the graph by keeping "bookmarks" which are pointers
/// to nodes within the graph. Each edge connecting two nodes has a piece
/// of data associated with it.
///
/// Clients interact with the graph through the following operations:
///  1) Create a new empty node and return a bookmark to it. This lets
///       you get started with a new, empty graph.
///  2) Create a new node connected to an existing node in the graph.
///       Clients specify which node to connect to, and which data should
///       be associated with the inbound and outbound edges.
///  3) Compute the path between two nodes. This path is returned to the
///       client as an array of data elements stored on the edges connecting
///       the two nodes.
///
/// The bidirectional node connections create retain cycles, which would
/// normally result in leaks. The use of bookmarks plus the limitation that
/// clients can only search through the graph based on bookmarks allows the
/// graph to track which nodes are reachable, and unreachable nodes are
/// automatically cleaned up.
///
/// The graph class doesn't actually contain any data. Bookmarks hold all
/// the necessary references to keep nodes alive and perform pathing. Having
/// everything go through a centralized object helps keep things more organized,
/// and if we ever did need centralized management (e.g. for thread safety)
/// this would provide a convenient place to put it.
class BookmarkableGraph<EdgeData> {
    typealias Bookmark = BookmarkableGraphBookmark<EdgeData>
    
    /// Add an empty node to the graph and return a bookmark to that node.
    func addEmptyNode() -> Bookmark {
        return Bookmark(graph: self, node: Node())
    }
    
    /// Add a new node to the graph connected to an existing node, and return a bookmark
    /// to the new node.
    ///
    /// - parameter fromBookmark: A bookmark to the node to connect the new node to.
    /// - parameter outboundData: The data to associate with the edge connecting `fromBookmark`
    ///                           to the new node.
    /// - parameter inboundData: The data to associate with the edge connecting the new node
    ///                          to `fromBookmark`.
    /// - returns: A bookmark to the newly created node.
    func addNode(fromBookmark: Bookmark, outboundData: EdgeData, inboundData: EdgeData) -> Bookmark {
        let newNode = Node()
        fromBookmark.node.edges.append((newNode, outboundData))
        newNode.edges.append((fromBookmark.node, inboundData))
        return Bookmark(graph: self, node: newNode)
    }
    
    /// Compute the path between two bookmarks, returning the data stored in the edges along the way.
    /// If there is no path between the two nodes then a fatal error is thrown.
    ///
    /// - Parameters:
    ///   - from: The bookmark to start from.
    ///   - to: The bookmark to search for.
    /// - Returns: An array of data elements leading from `from` to `to`.
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
    
    /// Remove a bookmark from the graph. This notes the node as no longer being
    /// bookmarked, and if the node has become unreachable, unlinks the node
    /// from the graph along with any other nodes that are made unreachable
    /// in the process.
    ///
    /// - Parameter bookmark: The bookmark to remove.
    func remove(bookmark: Bookmark) {
        bookmark.node.hasBookmark = false
        
        var node = bookmark.node
        while !node.hasBookmark && node.edges.count == 1 {
            removeInboundEdges(node: node)
            node = node.edges[0].node
        }
    }
    
    /// Remove the edges pointing to the given node in the graph.
    private func removeInboundEdges(node: Node) {
        for edge in node.edges {
            edge.node.edges.removeOne({ $0.node === node })
        }
    }
}

extension BookmarkableGraph {
    /// In order to test proper cleanup of unreachable nodes, the tests want
    /// to be able to directly refer to the nodes. This method provides
    /// access to them without exposing the private node type. Don't call
    /// this method from real code.
    func nodeForBookmarkForTesting(_ bookmark: Bookmark) -> AnyObject {
        return bookmark.node
    }
}

/// A bookmark representing a node within a `BookmarkableGraph`.
class BookmarkableGraphBookmark<EdgeData> {
    fileprivate let graph: BookmarkableGraph<EdgeData>
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
