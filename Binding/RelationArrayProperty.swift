//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import libRelational

public class RowArrayElement: ArrayElement {
    public typealias ID = RelationValue
    public typealias Data = Row

    public let id: RelationValue
    public var data: Row
    
    init(id: RelationValue, data: Row) {
        self.id = id
        self.data = data
    }
}

private typealias Element = RowArrayElement
private typealias Pos = ArrayPos<Element>
private typealias Change = ArrayChange<Element>

public class RelationArrayProperty: ArrayProperty<RowArrayElement>, AsyncRelationChangeCoalescedObserver {
    
    private let relation: Relation
    private let idAttr: Attribute
    private let orderAttr: Attribute
    
    private var removal: ObserverRemoval?

    fileprivate init(relation: Relation, idAttr: Attribute, orderAttr: Attribute) {
        precondition(relation.scheme.attributes.isSuperset(of: [idAttr, orderAttr]))
        
        self.relation = relation
        self.idAttr = idAttr
        self.orderAttr = orderAttr

        let (signal, notify) = Signal<SignalChange>.pipe()
        super.init(signal: signal, notify: notify)
    }
    
    deinit {
        removal?()
    }
    
    public override func start() {
        removal = relation.addAsyncObserver(self)
        
        notify.valueWillChange()
        relation.asyncAllRows({ result in
            if let rows = result.ok {
                let sortedRows = rows.sorted{ $0[self.orderAttr] < $1[self.orderAttr] }
                let elements = sortedRows.map{ RowArrayElement(id: $0[self.idAttr], data: $0) }
                self.elements = elements
                self.notifyObservers(arrayChanges: [.initial(elements)])
            }
            self.notify.valueDidChange()
        })
    }
    
    private func onInsert(_ rows: [Row], elems: inout [Element], changes: inout [Change]) {

        func insertElement(_ element: Element) -> Int {
            return elems.insertSorted(element, { $0.data[self.orderAttr] })
        }

        func insertRow(_ row: Row) -> Int {
            let id = row[self.idAttr]
            let element = RowArrayElement(id: id, data: row)
            return insertElement(element)
        }
        
        for row in rows {
            let index = insertRow(row)
            changes.append(.insert(index))
        }
    }

    private func onDelete(_ ids: [RelationValue], elems: inout [Element], changes: inout [Change]) {
        for id in ids {
            if let index = elems.index(where: { $0.id == id }) {
                elems.remove(at: index)
                changes.append(.delete(index))
            }
        }
    }

    private func onUpdate(_ rows: [Row], elems: inout [Element], changes: inout [Change]) {
        for row in rows {
            let newOrder = row[orderAttr]
            if newOrder != .notFound {
                let id = row[idAttr]
                if let element = elementForID(id, elems) {
                    changes.append(onMove(element, dstOrder: newOrder, elems: &elems))
                }
            }
        }
    }
    
    private func onMove(_ element: Element, dstOrder: RelationValue, elems: inout [Element]) -> Change {
        // Remove the element from the array
        let srcIndex = indexForID(element.id, elems)!
        _ = elems.remove(at: srcIndex)
        
        // Update the order value in the element's row
        element.data[orderAttr] = dstOrder
        
        // Insert the element in its new position
        let dstIndex = elems.insertSorted(element, { $0.data[self.orderAttr] })
        
        return .move(srcIndex: srcIndex, dstIndex: dstIndex)
    }
    
    private func adjacentElementsForIndex(_ index: Int, notMatching element: Element, inElements elems: [Element]) -> (Element?, Element?) {
        // Note: In the case where an element is being reordered, the array will still contain that element,
        // but `index` represents the new position assuming it was already removed, so we use the `notMatching`
        // element to avoid choosing that same element again.
        
        func elementAtIndex(_ i: Int, alt: Int) -> Element? {
            if let e = elems[safe: i] {
                if e !== element {
                    return e
                } else {
                    return elems[safe: alt]
                }
            } else {
                return nil
            }
        }
        
        let lo = elementAtIndex(index - 1, alt: index - 2)
        let hi = elementAtIndex(index,     alt: index + 1)
        return (lo, hi)
    }
    
    private func orderForElementBetween(_ previous: Element?, _ next: Element?, elems: [Element]) -> Double {
        let prev: Element?
        if previous == nil && next == nil {
            // Add after the last element
            prev = elems.last
        } else {
            // Insert after previous element
            prev = previous
        }
        
        // TODO: Use a more appropriate data type for storing order
        func orderForElement(_ element: Element) -> Double {
            return element.data[orderAttr].get()!
        }
        
        let lo: Double = prev.map(orderForElement) ?? 1.0
        let hi: Double = next.map(orderForElement) ?? 9.0
        return lo + ((hi - lo) / 2.0)
    }
    
    override public func orderForPos(_ pos: ArrayPos<RowArrayElement>) -> Double {
        let elems = self.elements ?? []
        let prev = pos.previousID.flatMap{ elementForID($0, elems) }
        let next = pos.nextID.flatMap{ elementForID($0, elems) }
        return orderForElementBetween(prev, next, elems: elems)
    }
    
    override public func orderForMove(srcIndex: Int, dstIndex: Int) -> Double {
        // Note: dstIndex is relative to the state of the array *after* the item is removed
        let elems = self.elements ?? []
        let element = elems[srcIndex]
        let (prev, next) = adjacentElementsForIndex(dstIndex, notMatching: element, inElements: elems)
        return orderForElementBetween(prev, next, elems: elems)
    }

    // TODO: This shouldn't be public
    public func relationWillChange(_ relation: Relation) {
        notify.valueWillChange()
    }

    // TODO: This shouldn't be public
    public func relationDidChange(_ relation: Relation, result: Result<NegativeSet<Row>, RelationError>) {
        switch result {
        case .Ok(let rows):
            // Compute array changes
            var arrayChanges: [Change] = []
            let parts = partsOf(rows, idAttr: self.idAttr)

            // TODO: Can we assume (or rather, should we require) that the initial data was
            // loaded by this point?
            if elements == nil {
                elements = []
            }
            
            self.onInsert(parts.addedRows, elems: &self.elements!, changes: &arrayChanges)
            self.onUpdate(parts.updatedRows, elems: &self.elements!, changes: &arrayChanges)
            self.onDelete(parts.deletedIDs, elems: &self.elements!, changes: &arrayChanges)

            self.notifyObservers(arrayChanges: arrayChanges)
            self.notify.valueDidChange()
            
        case .Err(let err):
            // TODO: actual handling
            fatalError("Got error for relation change: \(err)")
        }
    }
}

extension Relation {
    /// Returns an ArrayProperty that gets its data from this relation.
    public func arrayProperty(idAttr: Attribute, orderAttr: Attribute) -> ArrayProperty<RowArrayElement> {
        return RelationArrayProperty(relation: self, idAttr: idAttr, orderAttr: orderAttr)
    }
}
