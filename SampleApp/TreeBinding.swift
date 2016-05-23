//
//  TreeBinding.swift
//  Relational
//
//  Created by Chris Campbell on 5/23/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Foundation

public protocol TreeData {
    associatedtype ID: Equatable, Plistable
}

public class TreeNode<D: TreeData> {
    let id: D.ID
    var data: D
    var children: [TreeNode<D>]
    
    init(id: D.ID, data: D, children: [TreeNode<D>] = []) {
        self.id = id
        self.data = data
        self.children = children
    }
    
    public var parentID: D.ID? {
        return nil
    }
}

public struct TreePath<D: TreeData> {
    let parent: TreeNode<D>?
    let index: Int
}

extension TreePath: Equatable {}
public func ==<D: TreeData>(a: TreePath<D>, b: TreePath<D>) -> Bool {
    return a.parent?.id == b.parent?.id && a.index == b.index
}

public struct TreePos<D: TreeData> {
    let parentID: D.ID?
    let previousID: D.ID?
    let nextID: D.ID?
}

public enum TreeChange<D: TreeData> { case
    Insert(TreePath<D>),
    Delete(TreePath<D>),
    Move(src: TreePath<D>, dst: TreePath<D>)
}

extension TreeChange: Equatable {}
public func ==<D: TreeData>(a: TreeChange<D>, b: TreeChange<D>) -> Bool {
    switch (a, b) {
    case let (.Insert(a), .Insert(b)): return a == b
    case let (.Delete(a), .Delete(b)): return a == b
    case let (.Move(asrc, adst), .Move(bsrc, bdst)): return asrc == bsrc && adst == bdst
    default: return false
    }
}

public class TreeBinding<D: TreeData>: Binding {
    public typealias Value = TreeNode<D>
    public typealias Changes = [TreeChange<D>]

    public typealias ChangeObserver = ([TreeChange<D>]) -> Void
    public typealias ObserverRemoval = Void -> Void

    public typealias NodeID = D.ID
    public typealias Node = TreeNode<D>
    public typealias Path = TreePath<D>
    public typealias Pos = TreePos<D>
    public typealias Change = TreeChange<D>
    
    public let root: Node
    
    public var value: Node {
        return root
    }
    
    init(root: Node) {
        self.root = root
    }
    
    private var changeObservers: [UInt64: ChangeObserver] = [:]
    private var changeObserverNextID: UInt64 = 0
    
    public func addChangeObserver(observer: ChangeObserver) -> ObserverRemoval {
        let id = changeObserverNextID
        changeObserverNextID += 1
        changeObservers[id] = observer
        return { self.changeObservers.removeValueForKey(id) }
    }
    
    internal func notifyChangeObservers(changes: [TreeChange<D>]) {
        for (_, f) in changeObservers {
            f(changes)
        }
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
