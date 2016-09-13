//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import libRelational

public protocol ArrayElement: class, Equatable {
    associatedtype ID: Hashable, Plistable
    associatedtype Data
    
    var id: ID { get }
    var data: Data { get set }
}

public func ==<E: ArrayElement>(a: E, b: E) -> Bool {
    return a.id == b.id
}

public struct ArrayPos<E: ArrayElement> {
    let previousID: E.ID?
    let nextID: E.ID?
}

public enum ArrayChange<E: ArrayElement> { case
    initial([E]),
    insert(Int),
    delete(Int),
    move(srcIndex: Int, dstIndex: Int)
}

extension ArrayChange: Equatable {}
public func ==<E: ArrayElement>(a: ArrayChange<E>, b: ArrayChange<E>) -> Bool {
    switch (a, b) {
    case let (.initial(a), .initial(b)): return a == b
    case let (.insert(a), .insert(b)): return a == b
    case let (.delete(a), .delete(b)): return a == b
    case let (.move(asrc, adst), .move(bsrc, bdst)): return asrc == bsrc && adst == bdst
    default: return false
    }
}

open class ArrayProperty<E: ArrayElement>: AsyncReadablePropertyType {
    public typealias Value = [E]
    public typealias SignalChange = [ArrayChange<E>]
    
    public typealias ElementID = E.ID
    public typealias Element = E
    public typealias Pos = ArrayPos<E>
    public typealias Change = ArrayChange<E>

    internal var elements: [Element]?

    open var value: [Element]? {
        return elements
    }
    
    open let signal: Signal<SignalChange>
    internal let notify: Signal<SignalChange>.Notify
    
    init(signal: Signal<SignalChange>, notify: Signal<SignalChange>.Notify) {
        self.elements = nil
        self.signal = signal
        self.notify = notify
    }
    
    open func start() {
    }
    
    internal func notifyObservers(arrayChanges: [ArrayChange<E>]) {
        let metadata = ChangeMetadata(transient: false)
        notify.valueChanging(arrayChanges, metadata)
    }
    
    open func insert(_ row: E.Data, pos: Pos) {
    }
    
    open func delete(_ id: E.ID) {
    }
    
    open func move(srcIndex: Int, dstIndex: Int) {
    }
    
    /// Returns the index of the element with the given ID, relative to the sorted elements array.
    open func indexForID(_ id: E.ID, _ elements: [Element]) -> Int? {
        return elements.index(where: { $0.id == id })
    }
    
    /// Returns the element with the given ID.
    open func elementForID(_ id: E.ID, _ elements: [Element]) -> Element? {
        return indexForID(id, elements).map{ elements[$0] }
    }
}
