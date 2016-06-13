//
//  ObservableArray.swift
//  Relational
//
//  Created by Chris Campbell on 5/23/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Foundation

public protocol ArrayElement: class {
    associatedtype ID: Hashable, Plistable
    associatedtype Data
    
    var id: ID { get }
    var data: Data { get set }
}

public struct ArrayPos<E: ArrayElement> {
    let previousID: E.ID?
    let nextID: E.ID?
}

public enum ArrayChange { case
    Insert(Int),
    Delete(Int),
    Move(srcIndex: Int, dstIndex: Int)
}

extension ArrayChange: Equatable {}
public func ==(a: ArrayChange, b: ArrayChange) -> Bool {
    switch (a, b) {
    case let (.Insert(a), .Insert(b)): return a == b
    case let (.Delete(a), .Delete(b)): return a == b
    case let (.Move(asrc, adst), .Move(bsrc, bdst)): return asrc == bsrc && adst == bdst
    default: return false
    }
}

public class ObservableArray<E: ArrayElement>: Observable {
    public typealias Value = [E]
    public typealias Changes = [ArrayChange]
    public typealias ChangeObserver = Changes -> Void
    
    public typealias ElementID = E.ID
    public typealias Element = E
    public typealias Pos = ArrayPos<E>
    public typealias Change = ArrayChange

    internal(set) public var elements: [Element] = []
    
    public var value: [Element] {
        return elements
    }
    
    private var changeObservers: [UInt64: ChangeObserver] = [:]
    private var changeObserverNextID: UInt64 = 0

    init(elements: [Element]) {
        self.elements = elements
    }
    
    public func addChangeObserver(observer: ChangeObserver) -> ObserverRemoval {
        let id = changeObserverNextID
        changeObserverNextID += 1
        changeObservers[id] = observer
        return { self.changeObservers.removeValueForKey(id) }
    }
    
    internal func notifyChangeObservers(changes: Changes) {
        for (_, f) in changeObservers {
            f(changes)
        }
    }
    
    public func insert(row: E.Data, pos: Pos) {
    }
    
    public func delete(id: E.ID) {
    }
    
    public func move(srcIndex srcIndex: Int, dstIndex: Int) {
    }
    
    /// Returns the index of the element with the given ID, relative to the sorted elements array.
    public func indexForID(id: E.ID) -> Int? {
        return elements.indexOf({ $0.id == id })
    }
    
    /// Returns the element with the given ID.
    public func elementForID(id: E.ID) -> Element? {
        return indexForID(id).map{ elements[$0] }
    }
}
