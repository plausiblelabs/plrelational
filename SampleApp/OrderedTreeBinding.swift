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

public protocol OrderedTreeBindingObserver: class {
    func onInsert(path: TreePath)
    func onDelete(path: TreePath)
    func onMove(srcPath srcPath: TreePath, dstPath: TreePath)
}

public class OrderedTreeBinding {

    public class Node {
        var data: Row
        var children: [Node]
        
        init(_ data: Row, children: [Node] = []) {
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
    
    public let root: Node = Node(Row())
    
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
            for change in changes {
                switch change {
                case let .Add(row):
                    self.onInsert(row)
                case let .Delete(terms):
                    self.onDelete(terms)
                case let .Update(terms, row):
                    self.onUpdate(terms, row: row)
                }
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
            return parent.children.insertSorted(node, { (n) -> Double in n.data[self.orderAttr].get()! })
        }

        let node = Node(row)
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
        transaction[tableName].delete(idAttr *== id)
    }
    
    private func onDelete(query: SelectExpression) {
        
        func deleteNode(node: Node, inout _ nodes: [Node]) -> Int {
            let index = nodes.indexOf({$0 === node})!
            nodes.removeAtIndex(index)
            return index
        }
        
        // XXX: We have to dig out the identifier of the item to be deleted here
        let id = (query as! SelectExpressionBinaryOperator).rhs as! RelationValue

        // TODO: Delete all children too!
        
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
            relation.delete(idAttr *== id)
            
            let path = TreePath(parent: parent, index: index)
            observers.forEach{$0.onDelete(path)}
        }
    }

    /// Note: dstPath.index is relative to the state of the array *after* the item is removed.
    public func move(transaction: ChangeLoggingDatabase.Transaction, srcPath: TreePath, dstPath: TreePath) {
        let srcParent = srcPath.parent ?? root
        let node = srcParent.children[srcPath.index]
        let srcID = node.data[idAttr]
        
        let dstParentID: RelationValue
        if let dstParent = dstPath.parent {
            dstParentID = dstParent.data[idAttr]
        } else {
            dstParentID = .NULL
        }

        // TODO: Calculate new order value
//        // XXX: This is embarrassing
//        let previousID: RelationValue?
//        if dstIndex == 0 {
//            previousID = nil
//        } else {
//            let previousNode = dstParent.children[dstIndex - 1]
//            previousID = previousNode.data[idAttr]
//        }
//        let nextID: RelationValue?
//        if dstIndex >= dstParent.children.count - 1 {
//            nextID = nil
//        } else {
//            let nextNode = dstParent.children[dstIndex + 1]
//            nextID = nextNode.data[idAttr]
//        }
//        
//        let newPos = TreePos(parentID: dstPath.parent?.data[idAttr], previousID: previousID, nextID: nextID)
//        let newOrder = orderForPos(newPos)
        let newOrder = RelationValue(5.0)
        
        transaction[tableName].update(idAttr *== srcID, newValues: [
            parentAttr: dstParentID,
            orderAttr: newOrder
        ])
    }

    private func onUpdate(query: SelectExpression, row: Row) {
        // XXX: We have to dig out the identifier of the item to be moved here
        //let id = terms.first!.rhs as! RelationValue

        // TODO: Get tree path for item at `id`
        // TODO: Determine destination tree path using updated row values
        //onMove(srcPath: srcPath, dstPath: dstPath)
    }
    
    private func onMove(srcPath srcPath: TreePath, dstPath: TreePath) {
        let srcParent = srcPath.parent ?? root
        let dstParent = dstPath.parent ?? root
        
        // Note that dstPath.index of -1 can occur in the case where a node is being dragged onto another
        // (and srcPath.index can also be -1 in the undo case)
        let srcIndex: Int
        if srcPath.index < 0 {
            srcIndex = 0
        } else {
            srcIndex = srcPath.index
        }
        let dstIndex: Int
        if dstPath.index < 0 {
            dstIndex = dstParent.children.count
        } else {
            dstIndex = dstPath.index
        }
        
        let node = srcParent.children.removeAtIndex(srcIndex)
        if dstIndex < dstParent.children.count {
            dstParent.children.insert(node, atIndex: dstIndex)
        } else {
            dstParent.children.append(node)
        }
        
        // Create fresh paths using the adjusted index values since NSOutlineView will balk at
        // a negative source index
        let newSrcPath = TreePath(parent: srcPath.parent, index: srcIndex)
        let newDstPath = TreePath(parent: dstPath.parent, index: dstIndex)
        observers.forEach{$0.onMove(srcPath: newSrcPath, dstPath: newDstPath)}
    }
    
    private func orderForPos(pos: TreePos) -> RelationValue {
        // TODO: Use a more appropriate data type for storing order
        let lo: Double = orderForID(pos.previousID) ?? 1.0
        let hi: Double = orderForID(pos.nextID) ?? 9.0
        return RelationValue(lo + ((hi - lo) / 2.0))
    }
    
    // XXX
    private func orderForID(id: RelationValue?) -> Double? {
        if let id = id {
            if let node = nodeForID(id) {
                let row = node.data
                return row[orderAttr].get()
            } else {
                return nil
            }
        } else {
            return nil
        }
    }
}
