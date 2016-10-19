//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

public protocol TreeNode: CollectionElement {
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
    initial(N),
    insert(TreePath<N>),
    delete(TreePath<N>),
    update(TreePath<N>),
    move(src: TreePath<N>, dst: TreePath<N>)
}

extension TreeChange: Equatable {}
public func ==<N: TreeNode>(a: TreeChange<N>, b: TreeChange<N>) -> Bool {
    switch (a, b) {
    // TODO: Compare node structures for the .Initial case?
    case (.initial, .initial): return true
    case let (.insert(a), .insert(b)): return a == b
    case let (.delete(a), .delete(b)): return a == b
    case let (.update(a), .update(b)): return a == b
    case let (.move(asrc, adst), .move(bsrc, bdst)): return asrc == bsrc && adst == bdst
    default: return false
    }
}

open class TreeProperty<Node: TreeNode>: AsyncReadablePropertyType {
    public typealias Value = Node
    public typealias SignalChange = [TreeChange<Node>]

    public internal(set) var root: Node
    
    public var value: Node? {
        return root
    }
    
    public let signal: Signal<SignalChange>
    internal let notify: Signal<SignalChange>.Notify
    
    init(root: Node, signal: Signal<SignalChange>, notify: Signal<SignalChange>.Notify) {
        self.root = root
        self.signal = signal
        self.notify = notify
    }
    
    open func start() {
    }
    
    internal func notifyObservers(treeChanges: [TreeChange<Node>]) {
        let metadata = ChangeMetadata(transient: false)
        notify.valueChanging(treeChanges, metadata)
    }
    
    /// Returns the node with the given identifier.
    public func nodeForID(_ id: Node.ID) -> Node? {
        // TODO: Not efficient, but whatever
        func findNode(_ node: Node) -> Node? {
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
    public func nodeAtPath(_ path: TreePath<Node>) -> Node? {
        let parent = path.parent ?? root
        return parent.children[safe: path.index]
    }
    
    /// Returns the parent of the given node.
    public func parentForID(_ id: Node.ID) -> Node? {
        if let node = nodeForID(id) {
            return parentForNode(node)
        } else {
            return nil
        }
    }
    
    /// Returns the parent of the given node.
    public func parentForNode(_ node: Node) -> Node? {
        if let parentID = node.parentID {
            return nodeForID(parentID)
        } else {
            return nil
        }
    }
    
    /// Returns the index of the given node relative to its parent.
    public func indexForID(_ id: Node.ID) -> Int? {
        if let node = nodeForID(id) {
            let parent = parentForNode(node) ?? root
            return parent.children.index(where: {$0 === node})
        } else {
            return nil
        }
    }
    
    /// Returns the index of the given node relative to its parent.
    public func indexForNode(_ node: Node) -> Int? {
        let parent = parentForNode(node) ?? root
        return parent.children.index(where: {$0 === node})
    }
    
    /// Returns the tree path of the given node.
    public func pathForNode(_ node: Node) -> TreePath<Node>? {
        let parent = parentForNode(node)
        let parentNode = parent ?? root
        if let index = parentNode.children.index(where: {$0 === node}) {
            return TreePath(parent: parent, index: index)
        } else {
            return nil
        }
    }
    
    /// Returns true if the first node is a descendent of (or the same as) the second node.
    public func isNodeDescendent(_ node: Node, ofAncestor ancestor: Node) -> Bool {
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
    
    /// Returns an order value that would be appropriate for a node to be appended as a
    /// child of the given parent.
    /// Note: This only works when there is a distinct "order" property for each element
    /// of type Double.
    public func orderForAppend(inParent parent: Node.ID?) -> Double {
        fatalError("Must be implemented by subclasses")
    }

    /// Returns an order value that would be appropriate for a node to be inserted as the
    /// next sibling after the given node.
    /// Note: This only works when there is a distinct "order" property for each element
    /// of type Double.
    public func orderForInsert(after previous: Node.ID) -> (parentID: Node.ID?, order: Double) {
        fatalError("Must be implemented by subclasses")
    }
    
    /// Returns an order value that would be appropriate for a node to be moved from
    /// its current position to the new destination position.
    /// Note: This only works when there is a distinct "order" property for each element
    /// of type Double.
    /// Note: dstPath.index is relative to the state of the array *after* the item is removed.
    public func orderForMove(srcPath: TreePath<Node>, dstPath: TreePath<Node>) -> (nodeID: Node.ID, dstParentID: Node.ID?, order: Double) {
        fatalError("Must be implemented by subclasses")
    }
}
