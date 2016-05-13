//
//  OrderedTreeBinding.swift
//  Relational
//
//  Created by Chris Campbell on 5/6/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Foundation
import libRelational

public struct TreePos {
    let parentID: RelationValue?
    let previousID: RelationValue?
    let nextID: RelationValue?
}

public struct TreePath {
    let parent: OrderedTreeBinding.Node?
    let index: Int
}

extension TreePath: Equatable {}
public func ==(a: TreePath, b: TreePath) -> Bool {
    return a.parent?.id == b.parent?.id && a.index == b.index
}

public protocol OrderedTreeBindingObserver: class {
    func onInsert(path: TreePath)
    func onDelete(path: TreePath)
    func onMove(srcPath srcPath: TreePath, dstPath: TreePath)
}

public class OrderedTreeBinding {

    public class Node {
        let id: RelationValue
        var data: Row
        var children: [Node]
        
        init(id: RelationValue, data: Row, children: [Node] = []) {
            self.id = id
            self.data = data
            self.children = children
        }
    }
    
    private let relation: ChangeLoggingRelation<SQLiteTableRelation>
    private let tableName: String
    // TODO: Make this private
    let idAttr: Attribute
    private let parentAttr: Attribute
    private let orderAttr: Attribute
    
    public let root: Node = Node(id: -1, data: Row())
    
    private var removal: ObserverRemoval!
    private var observers: [OrderedTreeBindingObserver] = []
    
    init(relation: ChangeLoggingRelation<SQLiteTableRelation>, tableName: String, idAttr: Attribute, parentAttr: Attribute, orderAttr: Attribute) {
        self.relation = relation
        self.tableName = tableName
        self.idAttr = idAttr
        self.parentAttr = parentAttr
        self.orderAttr = orderAttr
        
        // TODO: Depth
        // TODO: Sorting
        // TODO: Error handling
        // TODO: For now, we'll load the whole tree structure eagerly
        //let rows = relation.rows().map{$0.ok!}
        
        self.removal = relation.addChangeObserver({ changes in

            func handle(relation: Relation, _ f: (Row) -> Void) {
                for rowResult in relation.rows() {
                    switch rowResult {
                    case .Ok(let row):
                        f(row)
                    case .Err(let err):
                        // TODO: error handling again
                        fatalError("Error fetching rows: \(err)")
                    }
                }
            }
            
            if let adds = changes.added {
                let added: Relation
                if let removes = changes.removed {
                    added = adds.project([self.idAttr]).difference(removes.project([self.idAttr])).join(adds)
                } else {
                    added = adds
                }
                handle(added, self.onInsert)
            }
            
            if let adds = changes.added, removes = changes.removed {
                let updated = removes.project([self.idAttr]).join(adds)
                handle(updated, self.onUpdate)
            }

            if let removes = changes.removed {
                let removed: Relation
                if let adds = changes.added {
                    removed = removes.project([self.idAttr]).difference(adds.project([self.idAttr])).join(removes)
                } else {
                    removed = removes
                }
                // TODO: rather than iterate here, maybe hand the whole relation over to onDelete
                handle(removed, self.onDelete)
            }
        })
    }
    
    public func addObserver(observer: OrderedTreeBindingObserver) {
        if observers.indexOf({$0 === observer}) == nil {
            observers.append(observer)
        }
    }

    public func nodeForID(id: RelationValue) -> Node? {
        // TODO: Not efficient, but whatever
        func findNode(node: Node) -> Node? {
            let nodeID = node.data[idAttr]
            if nodeID == id {
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
    
    /// Returns the parent of the given node.
    public func parentForID(id: RelationValue) -> Node? {
        if let node = nodeForID(id) {
            return parentForNode(node)
        } else {
            return nil
        }
    }

    /// Returns the parent of the given node.
    public func parentForNode(node: Node) -> Node? {
        let parentID = node.data[parentAttr]
        return nodeForID(parentID)
    }

    /// Returns the index of the given node relative to its parent.
    public func indexForID(id: RelationValue) -> Int? {
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
    func isNodeDescendent(node: Node, ofAncestor ancestor: Node) -> Bool {
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
    
    public func insert(transaction: ChangeLoggingDatabase.Transaction, row: Row, pos: TreePos) {
        let parentIDValue = pos.parentID ?? .NULL
        let order: RelationValue = orderForPos(pos)
        
        var mutableRow = row
        mutableRow[parentAttr] = parentIDValue
        mutableRow[orderAttr] = order

        transaction[tableName].add(mutableRow)
    }
    
    private func onInsert(row: Row) {

        func insertNode(node: Node, parent: Node) -> Int {
            return parent.children.insertSorted(node, { self.orderForNode($0) })
        }

        let node = Node(id: row[idAttr], data: row)
        let parentID = row[parentAttr]
        let parent: Node?
        let index: Int
        if parentID != .NULL {
            let parentNode = nodeForID(parentID)!
            parent = parentNode
            index = insertNode(node, parent: parentNode)
        } else {
            parent = nil
            index = insertNode(node, parent: root)
        }
        
        let path = TreePath(parent: parent, index: index)
        observers.forEach{$0.onInsert(path)}
    }
    
    public func delete(transaction: ChangeLoggingDatabase.Transaction, id: RelationValue) {
        // TODO: Should we delete from the bottom up?  The way things are ordered now,
        // observers will only be notified in onDelete() for the ancestor node; would it
        // make more sense to notify observers about all children?
        transaction[tableName].delete(idAttr *== id)
        
        // TODO: There are probably more efficient ways to handle this, but for now we'll
        // use our tree structure to determine which children need to be deleted
        if let node = nodeForID(id) {
            for child in node.children {
                delete(transaction, id: child.id)
            }
        }
    }
    
    private func onDelete(row: Row) {
        
        func deleteNode(node: Node, inout _ nodes: [Node]) -> Int {
            let index = nodes.indexOf({$0 === node})!
            nodes.removeAtIndex(index)
            return index
        }
        
        let id = row[idAttr]
        if let node = nodeForID(id) {
            let parent: Node?
            let index: Int
            let parentID = node.data[parentAttr]
            if parentID != .NULL {
                let parentNode = nodeForID(parentID)!
                parent = parentNode
                index = deleteNode(node, &parentNode.children)
            } else {
                parent = nil
                index = deleteNode(node, &root.children)
            }
            
            let path = TreePath(parent: parent, index: index)
            observers.forEach{$0.onDelete(path)}
        }
    }

    /// Note: dstPath.index is relative to the state of the array *after* the item is removed.
    public func move(transaction: ChangeLoggingDatabase.Transaction, srcPath: TreePath, dstPath: TreePath) {
        let srcParent = srcPath.parent ?? root
        let dstParent = dstPath.parent ?? root

        let srcNode = srcParent.children[srcPath.index]
        let srcID = srcNode.data[idAttr]
        
        let dstParentID: RelationValue
        if let dstParent = dstPath.parent {
            dstParentID = dstParent.data[idAttr]
        } else {
            dstParentID = .NULL
        }
        
        // Note that dstPath.index of -1 can occur in the case where a node is being dragged onto another
        let dstIndex: Int
        if dstPath.index < 0 {
            dstIndex = dstParent.children.count
        } else {
            dstIndex = dstPath.index
        }
        
        // Determine the order of the node in its new parent and/or position
        let (previous, next) = adjacentNodesForIndex(dstIndex, inParent: dstParent, notMatching: srcNode)
        let newOrder = orderWithinParent(dstParent, previous: previous, next: next)
        
        transaction[tableName].update(idAttr *== srcID, newValues: [
            parentAttr: dstParentID,
            orderAttr: newOrder
        ])
    }

    private func onUpdate(row: Row) {
        let newParentID = row[parentAttr]
        let newOrder = row[orderAttr]
        if newParentID == .NotFound || newOrder == .NotFound {
            // TODO: We should be able to perform the move if only one of parent/order were updated
            return
        }

        // XXX: We have to dig out the identifier of the item to be moved here
        let srcID = row[idAttr]
        let srcNode = nodeForID(srcID)!
        onMove(srcNode, dstParentID: newParentID, dstOrder: newOrder)
    }
    
    private func onMove(node: Node, dstParentID: RelationValue, dstOrder: RelationValue) {
        let optSrcParent = parentForNode(node)
        let optDstParent: Node?
        if dstParentID == .NULL {
            optDstParent = nil
        } else {
            optDstParent = nodeForID(dstParentID)!
        }

        let srcParent = optSrcParent ?? root
        let dstParent = optDstParent ?? root

        // Remove the node from its current parent
        let srcIndex = srcParent.children.indexOf({ $0 === node })!
        srcParent.children.removeAtIndex(srcIndex)
        
        // Update the values in the node's row
        node.data[parentAttr] = dstParentID
        node.data[orderAttr] = dstOrder

        // Insert the node in its new parent
        let dstIndex = dstParent.children.insertSorted(node, { self.orderForNode($0) })

        // Notify observers
        let newSrcPath = TreePath(parent: optSrcParent, index: srcIndex)
        let newDstPath = TreePath(parent: optDstParent, index: dstIndex)
        observers.forEach{$0.onMove(srcPath: newSrcPath, dstPath: newDstPath)}
    }

    private func adjacentNodesForIndex(index: Int, inParent parent: Node, notMatching node: Node) -> (Node?, Node?) {
        // Note: In the case where a node is being reordered within its existing parent, `parent` will
        // still contain that node, but `index` represents the new position assuming it was already removed,
        // so we use the `notMatching` node to avoid choosing that same node again.
        
        func safeGet(i: Int) -> Node? {
            if i >= 0 && i < parent.children.count {
                return parent.children[i]
            } else {
                return nil
            }
        }
        
        func nodeAtIndex(i: Int, alt: Int) -> Node? {
            if let n = safeGet(i) {
                if n !== node {
                    return n
                } else {
                    return safeGet(alt)
                }
            } else {
                return nil
            }
        }
        
        let lo = nodeAtIndex(index - 1, alt: index - 2)
        let hi = nodeAtIndex(index,     alt: index + 1)
        return (lo, hi)
    }
    
    private func orderWithinParent(parent: Node, previous: Node?, next: Node?) -> RelationValue {
        let prev: Node?
        if previous == nil && next == nil {
            // Add after the last child
            prev = parent.children.last
        } else {
            // Insert after previous child
            prev = previous
        }
        let lo: Double = prev.map(orderForNode) ?? 1.0
        let hi: Double = next.map(orderForNode) ?? 9.0
        return RelationValue(lo + ((hi - lo) / 2.0))
    }
    
    private func orderForPos(pos: TreePos) -> RelationValue {
        let parent: Node
        if let parentID = pos.parentID {
            parent = nodeForID(parentID)!
        } else {
            parent = root
        }
        
        let previous = pos.previousID.flatMap(nodeForID)
        let next = pos.nextID.flatMap(nodeForID)
        
        return orderWithinParent(parent, previous: previous, next: next)
    }
    
    private func orderForNode(node: Node) -> Double {
        return node.data[orderAttr].get()!
    }
}
