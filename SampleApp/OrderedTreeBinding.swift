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
    
    private let relation: SQLiteTableRelation
    private let closures: SQLiteTableRelation
    private let idAttr: Attribute
    private let orderAttr: Attribute
    
    private(set) public var rows: [Box<Row>] = []
    
    private var observers: [OrderedTreeBindingObserver] = []
    
    init(relation: SQLiteTableRelation, closures: SQLiteTableRelation, idAttr: Attribute, orderAttr: Attribute) {
        self.relation = relation
        self.closures = closures
        self.idAttr = idAttr
        self.orderAttr = orderAttr
        
        // TODO: Depth
        // TODO: Sorting
        // TODO: Error handling
        self.rows = relation.rows().map{Box($0.ok!)}
    }
    
    public func addObserver(observer: OrderedTreeBindingObserver) {
        if observers.indexOf({$0 === observer}) == nil {
            observers.append(observer)
        }
    }
    
    public func insert(row: Row, pos: TreePos) {
        // TODO
    }
    
    public func delete(id: RelationValue) {
        // TODO
    }
}
