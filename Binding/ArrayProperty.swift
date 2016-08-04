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
    Initial([E]),
    Insert(Int),
    Delete(Int),
    Move(srcIndex: Int, dstIndex: Int)
}

extension ArrayChange: Equatable {}
public func ==<E: ArrayElement>(a: ArrayChange<E>, b: ArrayChange<E>) -> Bool {
    switch (a, b) {
    case let (.Initial(a), .Initial(b)): return a == b
    case let (.Insert(a), .Insert(b)): return a == b
    case let (.Delete(a), .Delete(b)): return a == b
    case let (.Move(asrc, adst), .Move(bsrc, bdst)): return asrc == bsrc && adst == bdst
    default: return false
    }
}

public class ArrayProperty<E: ArrayElement>: AsyncReadablePropertyType {
    public typealias Value = [E]
    public typealias SignalChange = [ArrayChange<E>]
    
    public typealias ElementID = E.ID
    public typealias Element = E
    public typealias Pos = ArrayPos<E>
    public typealias Change = ArrayChange<E>

    internal var elements: [Element]?

    public var value: [Element]? {
        return elements
    }
    
    public let signal: Signal<SignalChange>
    internal let notify: Signal<SignalChange>.Notify
    
    init(signal: Signal<SignalChange>, notify: Signal<SignalChange>.Notify) {
        self.elements = nil
        self.signal = signal
        self.notify = notify
    }
    
    public func start() {
    }
    
    internal func notifyObservers(arrayChanges arrayChanges: [ArrayChange<E>]) {
        let metadata = ChangeMetadata(transient: false)
        notify.valueChanging(change: arrayChanges, metadata: metadata)
    }
    
    public func insert(row: E.Data, pos: Pos) {
    }
    
    public func delete(id: E.ID) {
    }
    
    public func move(srcIndex srcIndex: Int, dstIndex: Int) {
    }
    
    /// Returns the index of the element with the given ID, relative to the sorted elements array.
    public func indexForID(id: E.ID, _ elements: [Element]) -> Int? {
        return elements.indexOf({ $0.id == id })
    }
    
    /// Returns the element with the given ID.
    public func elementForID(id: E.ID, _ elements: [Element]) -> Element? {
        return indexForID(id, elements).map{ elements[$0] }
    }
}
