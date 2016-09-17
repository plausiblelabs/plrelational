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
    initial(N),
    insert(TreePath<N>),
    delete(TreePath<N>),
    move(src: TreePath<N>, dst: TreePath<N>)
}

extension TreeChange: Equatable {}
public func ==<N: TreeNode>(a: TreeChange<N>, b: TreeChange<N>) -> Bool {
    switch (a, b) {
    // TODO: Compare node structures for the .Initial case?
    case (.initial, .initial): return true
    case let (.insert(a), .insert(b)): return a == b
    case let (.delete(a), .delete(b)): return a == b
    case let (.move(asrc, adst), .move(bsrc, bdst)): return asrc == bsrc && adst == bdst
    default: return false
    }
}

open class TreeProperty<N: TreeNode>: AsyncReadablePropertyType {
    public typealias Value = N
    public typealias SignalChange = [TreeChange<N>]

    public typealias NodeID = N.ID
    public typealias Node = N
    public typealias Path = TreePath<N>
    public typealias Pos = TreePos<N>
    public typealias Change = TreeChange<N>
    
    open var root: Node
    
    open var value: Node? {
        return root
    }
    
    open let signal: Signal<SignalChange>
    internal let notify: Signal<SignalChange>.Notify
    
    init(root: Node, signal: Signal<SignalChange>, notify: Signal<SignalChange>.Notify) {
        self.root = root
        self.signal = signal
        self.notify = notify
    }
    
    public func start() {
    }
    
    internal func notifyObservers(treeChanges: [TreeChange<N>]) {
        let metadata = ChangeMetadata(transient: false)
        notify.valueChanging(treeChanges, metadata)
    }
    
    open func insert(data: N.Data, pos: Pos) {
    }

    open func computeOrderForAppend(inParent parent: N.ID?) -> Double {
        return 0.0
    }

    open func computeOrderForInsert(after previous: N.ID) -> (N.ID?, Double) {
        return (nil, 0.0)
    }

    open func delete(_ id: N.ID) {
    }
    
    open func move(srcPath: Path, dstPath: Path) {
    }
    
    /// Returns the node with the given identifier.
    open func nodeForID(_ id: NodeID) -> Node? {
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
    open func nodeAtPath(_ path: Path) -> Node? {
        let parent = path.parent ?? root
        return parent.children[safe: path.index]
    }
    
    /// Returns the parent of the given node.
    open func parentForID(_ id: NodeID) -> Node? {
        if let node = nodeForID(id) {
            return parentForNode(node)
        } else {
            return nil
        }
    }
    
    /// Returns the parent of the given node.
    open func parentForNode(_ node: Node) -> Node? {
        if let parentID = node.parentID {
            return nodeForID(parentID)
        } else {
            return nil
        }
    }
    
    /// Returns the index of the given node relative to its parent.
    open func indexForID(_ id: NodeID) -> Int? {
        if let node = nodeForID(id) {
            let parent = parentForNode(node) ?? root
            return parent.children.index(where: {$0 === node})
        } else {
            return nil
        }
    }
    
    /// Returns the index of the given node relative to its parent.
    open func indexForNode(_ node: Node) -> Int? {
        let parent = parentForNode(node) ?? root
        return parent.children.index(where: {$0 === node})
    }
    
    /// Returns true if the first node is a descendent of (or the same as) the second node.
    open func isNodeDescendent(_ node: Node, ofAncestor ancestor: Node) -> Bool {
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
