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

class RelationArrayProperty: ArrayProperty<RowArrayElement>, AsyncRelationChangeCoalescedObserver {
    
    private let relation: Relation
    private let idAttr: Attribute
    private let orderAttr: Attribute
    
    private var removal: ObserverRemoval!

    init(relation: Relation, idAttr: Attribute, orderAttr: Attribute) {
        precondition(relation.scheme.attributes.isSupersetOf([idAttr, orderAttr]))
        
        self.relation = relation
        self.idAttr = idAttr
        self.orderAttr = orderAttr

        let (signal, notify) = Signal<SignalChange>.pipe()
        super.init(signal: signal, notify: notify)

        self.removal = relation.addAsyncObserver(self)
    }
    
    deinit {
        removal()
    }
    
    override func start() {
        notify.valueWillChange()
        relation.asyncAllRows({ result in
            if let rows = result.ok {
                let sortedRows = rows.sort{ $0[self.orderAttr] < $1[self.orderAttr] }
                let elements = sortedRows.map{ RowArrayElement(id: $0[self.idAttr], data: $0) }
                self.elements = elements
                self.notifyObservers(arrayChanges: [.Initial(elements)])
            }
            self.notify.valueDidChange()
        })
    }
    
    override func insert(row: Row, pos: Pos) {
        // TODO: Provide insert/delete/move as extension defined where R: TransactionalRelation
        guard let relation = relation as? TransactionalDatabase.TransactionalRelation else {
            fatalError("insert() is only supported when the underlying relation is mutable")
        }

        // Determine the position of the row to be inserted relative to the current array state
        var mutableRow = row
        let elems = elements ?? []
        mutableRow[orderAttr] = self.orderForPos(pos, elems: elems)

        // Insert into the relation
        relation.asyncAdd(mutableRow)
    }
    
    private func onInsert(rows: [Row], inout elems: [Element], inout changes: [Change]) {

        func insertElement(element: Element) -> Int {
            return elems.insertSorted(element, { $0.data[self.orderAttr] })
        }

        func insertRow(row: Row) -> Int {
            let id = row[self.idAttr]
            let element = RowArrayElement(id: id, data: row)
            return insertElement(element)
        }
        
        for row in rows {
            let index = insertRow(row)
            changes.append(.Insert(index))
        }
    }

    override func delete(id: RelationValue) {
        guard let relation = relation as? TransactionalDatabase.TransactionalRelation else {
            fatalError("delete() is only supported when the underlying relation is mutable")
        }

        // Delete from the relation
        relation.asyncDelete(self.idAttr *== id)
    }

    private func onDelete(ids: [RelationValue], inout elems: [Element], inout changes: [Change]) {
        for id in ids {
            if let index = elems.indexOf({ $0.id == id }) {
                elems.removeAtIndex(index)
                changes.append(.Delete(index))
            }
        }
    }

    /// Note: dstIndex is relative to the state of the array *after* the item is removed.
    override func move(srcIndex srcIndex: Int, dstIndex: Int) {
//        var elemID: RelationValue!
//        var newOrder: RelationValue!
//
//        // Determine the order of the element in its new position (relative to the current array state)
//        // TODO: Shouldn't we be doing this in the `workOn` context?
//        self.state.withValue{
//            let elems = $0.data ?? []
//            let element = elems[srcIndex]
//            elemID = element.id
//        
//            let (previous, next) = self.adjacentElementsForIndex(dstIndex, notMatching: element, inElements: elems)
//            newOrder = self.orderForElementBetween(previous, next, elems: elems)
//        }
//
//        // Update the relation
//        workOn.schedule{
//            var mutableRelation = self.relation
//            mutableRelation.update(self.idAttr *== elemID, newValues: [self.orderAttr: newOrder])
//        }
    }
    
    private func onUpdate(rows: [Row], inout elems: [Element], inout changes: [Change]) {
        for row in rows {
            let newOrder = row[orderAttr]
            if newOrder != .NotFound {
                let id = row[idAttr]
                let element = elementForID(id, elems)!
                changes.append(self.onMove(element, dstOrder: newOrder, elems: &elems))
            }
        }
    }
    
    // Must be called in the context of the `workOn` scheduler.
    private func onMove(element: Element, dstOrder: RelationValue, inout elems: [Element]) -> Change {
        // Remove the element from the array
        let srcIndex = indexForID(element.id, elems)!
        elems.removeAtIndex(srcIndex)
        
        // Update the order value in the element's row
        element.data[orderAttr] = dstOrder
        
        // Insert the element in its new position
        let dstIndex = elems.insertSorted(element, { $0.data[self.orderAttr] })
        
        return .Move(srcIndex: srcIndex, dstIndex: dstIndex)
    }
    
    private func adjacentElementsForIndex(index: Int, notMatching element: Element, inElements elems: [Element]) -> (Element?, Element?) {
        // Note: In the case where an element is being reordered, the array will still contain that element,
        // but `index` represents the new position assuming it was already removed, so we use the `notMatching`
        // element to avoid choosing that same element again.
        
        func elementAtIndex(i: Int, alt: Int) -> Element? {
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
    
    private func orderForElementBetween(previous: Element?, _ next: Element?, elems: [Element]) -> RelationValue {
        let prev: Element?
        if previous == nil && next == nil {
            // Add after the last element
            prev = elems.last
        } else {
            // Insert after previous element
            prev = previous
        }
        
        // TODO: Use a more appropriate data type for storing order
        func orderForElement(element: Element) -> Double {
            return element.data[orderAttr].get()!
        }
        
        let lo: Double = prev.map(orderForElement) ?? 1.0
        let hi: Double = next.map(orderForElement) ?? 9.0
        return RelationValue(lo + ((hi - lo) / 2.0))
    }
    
    private func orderForPos(pos: Pos, elems: [Element]) -> RelationValue {
        let prev = pos.previousID.flatMap{ elementForID($0, elems) }
        let next = pos.nextID.flatMap{ elementForID($0, elems) }
        return orderForElementBetween(prev, next, elems: elems)
    }
    
    func relationWillChange(relation: Relation) {
        notify.valueWillChange()
    }

    func relationDidChange(relation: Relation, result: Result<NegativeSet<Row>, RelationError>) {
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
    public func arrayProperty(idAttr: Attribute = "id", orderAttr: Attribute = "order") -> ArrayProperty<RowArrayElement> {
        return RelationArrayProperty(relation: self, idAttr: idAttr, orderAttr: orderAttr)
    }
}
