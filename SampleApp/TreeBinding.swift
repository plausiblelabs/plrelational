//
//  TreeBinding.swift
//  Relational
//
//  Created by Chris Campbell on 5/23/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Foundation

public protocol TreeData {
    associatedtype ID: Equatable
    var id: ID { get }
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
    
    public let root: TreeNode<D>
    
    public var value: TreeNode<D> {
        return root
    }
    
    init(root: TreeNode<D>) {
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
}
