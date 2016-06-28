//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

public protocol TreeNode: class {
    associatedtype ID: Hashable, Plistable
    associatedtype Data

    var id: ID { get }
    var data: Data { get set }
    var children: [Self] { get set }
    var parentID: ID? { get }
}

public struct TreePath<N: TreeNode> {
    public let parent: N?
    public let index: Int
    
    public init(parent: N?, index: Int) {
        self.parent = parent
        self.index = index
    }
}

extension TreePath: Equatable {}
public func ==<N: TreeNode>(a: TreePath<N>, b: TreePath<N>) -> Bool {
    return a.parent?.id == b.parent?.id && a.index == b.index
}

public struct TreePos<N: TreeNode> {
    public let parentID: N.ID?
    public let previousID: N.ID?
    public let nextID: N.ID?
    
    public init(parentID: N.ID?, previousID: N.ID?, nextID: N.ID?) {
        self.parentID = parentID
        self.previousID = previousID
        self.nextID = nextID
    }
}

public enum TreeChange<N: TreeNode> { case
    Insert(TreePath<N>),
    Delete(TreePath<N>),
    Move(src: TreePath<N>, dst: TreePath<N>)
}

extension TreeChange: Equatable {}
public func ==<N: TreeNode>(a: TreeChange<N>, b: TreeChange<N>) -> Bool {
    switch (a, b) {
    case let (.Insert(a), .Insert(b)): return a == b
    case let (.Delete(a), .Delete(b)): return a == b
    case let (.Move(asrc, adst), .Move(bsrc, bdst)): return asrc == bsrc && adst == bdst
    default: return false
    }
}

public class TreeProperty<N: TreeNode>: ReadablePropertyType {
    public typealias Value = N
    public typealias SignalChange = [TreeChange<N>]

    public typealias NodeID = N.ID
    public typealias Node = N
    public typealias Path = TreePath<N>
    public typealias Pos = TreePos<N>
    public typealias Change = TreeChange<N>
    
    public let root: Node
    
    public var value: Node {
        return root
    }
    
    public let signal: Signal<[Change]>
    private let notify: Signal<[Change]>.Notify
    
    init(root: Node) {
        (self.signal, self.notify) = Signal<[Change]>.pipe()
        self.root = root
    }
    
    internal func notifyChangeObservers(changes: [Change]) {
        let metadata = ChangeMetadata(transient: false)
        notify(change: changes, metadata: metadata)
    }
    
    // TODO: Move these to a MutableTreeProperty subclass?
    public func insert(data: N.Data, pos: Pos) {
    }
    
    public func delete(id: N.ID) {
    }
    
    public func move(srcPath srcPath: Path, dstPath: Path) {
    }
    
    /// Returns the node with the given identifier.
    public func nodeForID(id: NodeID) -> Node? {
        // TODO: Not efficient, but whatever
        func findNode(node: Node) -> Node? {
            if node.id == id {
                return node
            }
            
            for child in node.children {
                if let found = findNode(child) {
                    return found
                }
            }
            
            return nil
        }
        
        return findNode(root)
    }
    
    /// Returns the node at the given path.
    public func nodeAtPath(path: Path) -> Node? {
        let parent = path.parent ?? root
        return parent.children[safe: path.index]
    }
    
    /// Returns the parent of the given node.
    public func parentForID(id: NodeID) -> Node? {
        if let node = nodeForID(id) {
            return parentForNode(node)
        } else {
            return nil
        }
    }
    
    /// Returns the parent of the given node.
    public func parentForNode(node: Node) -> Node? {
        if let parentID = node.parentID {
            return nodeForID(parentID)
        } else {
            return nil
        }
    }
    
    /// Returns the index of the given node relative to its parent.
    public func indexForID(id: NodeID) -> Int? {
        if let node = nodeForID(id) {
            let parent = parentForNode(node) ?? root
            return parent.children.indexOf({$0 === node})
        } else {
            return nil
        }
    }
    
    /// Returns the index of the given node relative to its parent.
    public func indexForNode(node: Node) -> Int? {
        let parent = parentForNode(node) ?? root
        return parent.children.indexOf({$0 === node})
    }
    
    /// Returns true if the first node is a descendent of (or the same as) the second node.
    public func isNodeDescendent(node: Node, ofAncestor ancestor: Node) -> Bool {
        if node === ancestor {
            return true
        }
        
        // XXX: Again, inefficient
        var parent = parentForNode(node)
        while let p = parent {
            if p === ancestor {
                return true
            }
            parent = parentForNode(p)
        }
        
        return false
    }
}
