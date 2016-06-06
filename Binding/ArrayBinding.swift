//
//  ArrayBinding.swift
//  Relational
//
//  Created by Chris Campbell on 5/23/16.
//  Copyright © 2016 mikeash. All rights reserved.
//

import Foundation

public protocol ArrayData {
    associatedtype EID: Hashable, Plistable
}

public class ArrayElement<D: ArrayData> {
    public let id: D.EID
    public var data: D
    
    public init(id: D.EID, data: D) {
        self.id = id
        self.data = data
    }
}

public struct ArrayPos<D: ArrayData> {
    let previousID: D.EID?
    let nextID: D.EID?
}

public enum ArrayChange<D: ArrayData> { case
    Insert(Int),
    Delete(Int),
    Move(srcIndex: Int, dstIndex: Int)
}

extension ArrayChange: Equatable {}
public func ==<D: ArrayData>(a: ArrayChange<D>, b: ArrayChange<D>) -> Bool {
    switch (a, b) {
    case let (.Insert(a), .Insert(b)): return a == b
    case let (.Delete(a), .Delete(b)): return a == b
    case let (.Move(asrc, adst), .Move(bsrc, bdst)): return asrc == bsrc && adst == bdst
    default: return false
    }
}

public class ArrayBinding<D: ArrayData>: Binding {
    public typealias Value = [ArrayElement<D>]
    public typealias Changes = [ArrayChange<D>]
    public typealias ChangeObserver = Changes -> Void
    
    public typealias ElementID = D.EID
    public typealias Element = ArrayElement<D>
    public typealias Pos = ArrayPos<D>
    public typealias Change = ArrayChange<D>

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
    
    internal func notifyChangeObservers(changes: [ArrayChange<D>]) {
        for (_, f) in changeObservers {
            f(changes)
        }
    }
    
    /// Returns the index of the element with the given ID, relative to the sorted elements array.
    public func indexForID(id: D.EID) -> Int? {
        return elements.indexOf({ $0.id == id })
    }
    
    /// Returns the element with the given ID.
    public func elementForID(id: D.EID) -> Element? {
        return indexForID(id).map{ elements[$0] }
    }
}
