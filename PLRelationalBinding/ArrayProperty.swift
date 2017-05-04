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
    update(Int),
    move(srcIndex: Int, dstIndex: Int)
}

extension ArrayChange: Equatable {}
public func ==<E: ArrayElement>(a: ArrayChange<E>, b: ArrayChange<E>) -> Bool {
    switch (a, b) {
    case let (.initial(a), .initial(b)): return a == b
    case let (.insert(a), .insert(b)): return a == b
    case let (.delete(a), .delete(b)): return a == b
    case let (.update(a), .update(b)): return a == b
    case let (.move(asrc, adst), .move(bsrc, bdst)): return asrc == bsrc && adst == bdst
    default: return false
    }
}

open class ArrayProperty<Element: ArrayElement>: AsyncReadablePropertyType {
    public typealias Value = [Element]
    public typealias SignalChange = [ArrayChange<Element>]
    
    public internal(set) var elements: [Element]

    public var value: [Element]? {
        return elements
    }
    
    public let signal: Signal<SignalChange>
    
    init(signal: Signal<SignalChange>) {
        self.elements = []
        self.signal = signal
    }
    
//    open func startX() {
//    }
    
    public var property: AsyncReadableProperty<[Element]> {
        return fullArray()
    }
    
    /// Returns the index of the element with the given ID, relative to the sorted elements array.
    public func indexForID(_ id: Element.ID) -> Int? {
        return elements.index(where: { $0.id == id })
    }

    /// Returns the element with the given ID.
    public func elementForID(_ id: Element.ID) -> Element? {
        return indexForID(id).map{ elements[$0] }
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
    public func orderForMove(srcIndex: Int, dstIndex: Int) -> Double {
        fatalError("Must be implemented by subclasses")
    }
    
    /// Returns a view on this ArrayProperty that delivers the full array through
    /// its Signal whenever there is any change in the underlying ArrayProperty.
    public func fullArray() -> AsyncReadableProperty<[Element]> {
        return FullArrayProperty(underlying: self)
    }
}

private class FullArrayProperty<Element: ArrayElement>: AsyncReadableProperty<[Element]> {
    
    private let underlying: ArrayProperty<Element>
    
    fileprivate init(underlying: ArrayProperty<Element>) {
        self.underlying = underlying
        super.init(initialValue: underlying.value, signal: underlying.signal.map{ _ in return underlying.elements })
    }
    
//    fileprivate override func start() {
//        underlying.start()
//        super.start()
//    }
}
