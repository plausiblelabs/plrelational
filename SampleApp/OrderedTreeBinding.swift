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
    let indexes: [Int]
}

public protocol OrderedTreeBindingObserver: class {
    func onInsert(path: TreePath)
    func onDelete(path: TreePath)
    func onMove(srcPath srcPath: TreePath, dstPath: TreePath)
}

public class OrderedTreeBinding {

    public class Node {
        let data: Row
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

    public func nodeForID(id: Int64) -> Node? {
        // TODO: Not efficient, but whatever
        func findNode(node: Node) -> Node? {
            let nodeID: Int64 = node.data[idAttr].get()!
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
    
    // XXX: This is temporary
    func add(row: Row, parentID: Int64?) {
        let parentIDValue: RelationValue
        let pos: TreePos
        if let parentID = parentID {
            parentIDValue = RelationValue(parentID)
            let parentNode = nodeForID(parentID)
            pos = TreePos(parentID: parentIDValue, previousID: parentNode?.children.last?.data[idAttr], nextID: nil)
        } else {
            parentIDValue = .NULL
            pos = TreePos(parentID: nil, previousID: self.nodes.last?.data[idAttr], nextID: nil)
        }
        
        let order: RelationValue = orderForPos(pos)
        
        var mutableRow = row
        mutableRow["parent"] = parentIDValue
        mutableRow["order"] = order
        let node = Node(mutableRow)

        if let parentID = parentID {
            nodeForID(parentID)!.children.append(node)
        } else {
            self.nodes.append(node)
        }
        relation.add(mutableRow)
        
        // TODO: Update closure table
        // TODO: Notify observers
    }
    
//    public func insert(row: Row, pos: TreePos) {
//        // TODO
//    }

    public func delete(id: RelationValue) {
        // TODO
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
            // XXX: Don't assume Int64
            let idval: Int64 = id.get()!
            if let node = nodeForID(idval) {
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
