//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import libRelational

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

public class ArrayProperty<E: ArrayElement>: ReadablePropertyType {
    public typealias Value = AsyncState<[E]>
    public typealias SignalChange = [ArrayChange]
    
    public typealias ElementID = E.ID
    public typealias Element = E
    public typealias Pos = ArrayPos<E>
    public typealias Change = ArrayChange

    internal var state: Mutexed<AsyncState<[Element]>>

    public var value: AsyncState<[Element]> {
        return state.get()
    }
    
    public var elements: [Element] {
        return value.data ?? []
    }
    
    public let signal: Signal<[ArrayChange]>
    private let notify: Signal<[ArrayChange]>.Notify
    
    init(initialState: AsyncState<[Element]>) {
        (self.signal, self.notify) = Signal<[ArrayChange]>.pipe()
        self.state = Mutexed(initialState)
    }
    
    internal func notifyChangeObservers(changes: [ArrayChange]) {
        let metadata = ChangeMetadata(transient: false)
        notify(change: changes, metadata: metadata)
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
