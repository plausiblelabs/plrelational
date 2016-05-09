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
    
    private let relation: SQLiteTableRelation
    private let closures: SQLiteTableRelation
    // TODO: Make this private
    let idAttr: Attribute
    private let orderAttr: Attribute
    
    private(set) public var nodes: [Node] = []
    
    private var observers: [OrderedTreeBindingObserver] = []
    
    init(relation: SQLiteTableRelation, closures: SQLiteTableRelation, idAttr: Attribute, orderAttr: Attribute) {
        self.relation = relation
        self.closures = closures
        self.idAttr = idAttr
        self.orderAttr = orderAttr
        
        // TODO: Depth
        // TODO: Sorting
        // TODO: Error handling
        // TODO: For now, we'll load the whole tree structure eagerly
        //let rows = relation.rows().map{$0.ok!}
        self.nodes = []
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
        
        for node in nodes {
            if let found = findNode(node) {
                return found
            }
        }
        
        return nil
    }
    
    /// Returns the parent of the given node.
    public func parentForID(id: RelationValue) -> Node? {
        if let node = nodeForID(id) {
            let parentID = node.data["parent"]
            return nodeForID(parentID)
        } else {
            return nil
        }
    }

    /// Returns the index of the given node relative to its parent.
    public func indexForID(id: RelationValue) -> Int? {
        if let node = nodeForID(id) {
            let parentID = node.data["parent"]
            if let parent = nodeForID(parentID) {
                return parent.children.indexOf({$0 === node})
            } else {
                return nodes.indexOf({$0 === node})
            }
        } else {
            return nil
        }
    }
    
    public func insert(row: Row, pos: TreePos) {
        let parentIDValue = pos.parentID ?? .NULL
        let order: RelationValue = orderForPos(pos)
        
        var mutableRow = row
        mutableRow["parent"] = parentIDValue
        mutableRow[orderAttr] = order
        let node = Node(mutableRow)

        func insertNode(node: Node, inout _ nodes: [Node]) -> Int {
            let orderVal: Double = order.get()!
            
            // XXX: This is an inefficient way to do an order-preserving insert
            var index = 0
            for n in nodes {
                let o: Double = n.data[orderAttr].get()!
                if o > orderVal {
                    break
                }
                index += 1
            }
            
            if index < nodes.count {
                nodes.insert(node, atIndex: index)
            } else {
                nodes.append(node)
            }
            
            return index
        }

        let parent: Node?
        let index: Int
        if let parentID = pos.parentID {
            let parentNode = nodeForID(parentID)!
            parent = parentNode
            index = insertNode(node, &parentNode.children)
        } else {
            parent = nil
            index = insertNode(node, &self.nodes)
        }
        relation.add(mutableRow)
        
        // TODO: Update closure table
        let path = TreePath(parent: parent, index: index)
        observers.forEach{$0.onInsert(path)}
    }
    
    public func delete(id: RelationValue) {
        
        func deleteNode(node: Node, inout _ nodes: [Node]) -> Int {
            let index = nodes.indexOf({$0 === node})!
            nodes.removeAtIndex(index)
            return index
        }
        
        // TODO: Delete all children too!
        
        if let node = nodeForID(id) {
            let parent: Node?
            let index: Int
            // TODO: Make parent attribute name configurable
            let parentID = node.data["parent"]
            if parentID != .NULL {
                let parentNode = nodeForID(parentID)!
                parent = parentNode
                index = deleteNode(node, &parentNode.children)
            } else {
                parent = nil
                index = deleteNode(node, &self.nodes)
            }
            relation.delete([.EQ(idAttr, id)])
            
            // TODO: Update closure table
            let path = TreePath(parent: parent, index: index)
            observers.forEach{$0.onDelete(path)}
        }
    }
    
    /// Note: dstIndex is relative to the state of the array *after* the item is removed.
    // TODO: For now we only support reordering within the same parent
    public func move(parent parent: Node?, srcIndex: Int, dstIndex: Int) {
        
        func moveNode(inout nodes: [Node]) {
            let node = nodes.removeAtIndex(srcIndex)
            nodes.insert(node, atIndex: dstIndex)
            
            // XXX: This is embarrassing
            let previousID: RelationValue?
            if dstIndex == 0 {
                previousID = nil
            } else {
                let previousNode = nodes[dstIndex - 1]
                previousID = previousNode.data[idAttr]
            }
            let nextID: RelationValue?
            if dstIndex >= nodes.count - 1 {
                nextID = nil
            } else {
                let nextNode = nodes[dstIndex + 1]
                nextID = nextNode.data[idAttr]
            }
            
            let newPos = TreePos(parentID: parent?.data[idAttr], previousID: previousID, nextID: nextID)
            let newOrder = orderForPos(newPos)
            node.data[orderAttr] = newOrder
        }

        if let parent = parent {
            moveNode(&parent.children)
        } else {
            moveNode(&self.nodes)
        }
        
        // TODO: Update the underlying tables too!
        
        let srcPath = TreePath(parent: parent, index: srcIndex)
        let dstPath = TreePath(parent: parent, index: dstIndex)
        observers.forEach{$0.onMove(srcPath: srcPath, dstPath: dstPath)}
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
