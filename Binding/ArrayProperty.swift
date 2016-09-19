//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation

public protocol ArrayElement: CollectionElement, Equatable {
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

open class ArrayProperty<Element: ArrayElement>: AsyncReadablePropertyType {
    public typealias Value = [Element]
    public typealias SignalChange = [ArrayChange<Element>]
    
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
    
    internal func notifyObservers(arrayChanges: [ArrayChange<Element>]) {
        let metadata = ChangeMetadata(transient: false)
        notify.valueChanging(arrayChanges, metadata)
    }

    // TODO: If we make elements non-optional, we can drop the variants that take an element array
    // as an argument.
    
    /// Returns the index of the element with the given ID, relative to the sorted elements array.
    public func indexForID(_ id: Element.ID) -> Int? {
        return indexForID(id, self.elements ?? [])
    }

    /// Returns the index of the element with the given ID, relative to the sorted elements array.
    public func indexForID(_ id: Element.ID, _ elements: [Element]) -> Int? {
        return elements.index(where: { $0.id == id })
    }

    /// Returns the element with the given ID.
    public func elementForID(_ id: Element.ID) -> Element? {
        return elementForID(id, self.elements ?? [])
    }

    /// Returns the element with the given ID.
    public func elementForID(_ id: Element.ID, _ elements: [Element]) -> Element? {
        return indexForID(id, elements).map{ elements[$0] }
    }
    
    /// Returns an order value that would be appropriate for an element to be inserted at
    /// the given position, relative the current array.
    /// Note: This only works when there is a distinct "order" property for each element
    /// of type Double.
    public func orderForPos(_ pos: ArrayPos<Element>) -> Double {
        fatalError("Must be implemented by subclasses")
    }
    
    /// Returns an order value that would be appropriate for an element to be moved from
    /// its current index to the new destination index.
    /// Note: This only works when there is a distinct "order" property for each element
    /// of type Double.
    /// Note: dstIndex is relative to the state of the array *after* the item is removed.
    func orderForMove(srcIndex: Int, dstIndex: Int) -> Double {
        fatalError("Must be implemented by subclasses")
    }
}
