//
// Copyright (c) 2016 Plausible Labs Cooperative, Inc.
// All rights reserved.
//

import Foundation
import libRelational

open class RowArrayElement: ArrayElement {
    public typealias ID = RelationValue
    public typealias Data = Row

    open let id: RelationValue
    open var data: Row
    
    init(id: RelationValue, data: Row) {
        self.id = id
        self.data = data
    }
}

class RelationArrayProperty: ArrayProperty<RowArrayElement>, AsyncRelationChangeCoalescedObserver {
    
    fileprivate let relation: Relation
    fileprivate let idAttr: Attribute
    fileprivate let orderAttr: Attribute
    
    fileprivate var removals: [ObserverRemoval] = []

    init(relation: Relation, idAttr: Attribute, orderAttr: Attribute) {
        precondition(relation.scheme.attributes.isSuperset(of: [idAttr, orderAttr]))
        
        self.relation = relation
        self.idAttr = idAttr
        self.orderAttr = orderAttr

        let (signal, notify) = Signal<SignalChange>.pipe()
        super.init(signal: signal, notify: notify)

        removals.append(relation.addAsyncObserver(self))
    }
    
    deinit {
        removals.forEach{$0()}
    }
    
    override func start() {
        notify.valueWillChange()
        relation.asyncAllRows({ result in
            if let rows = result.ok {
                let sortedRows = rows.sorted{ $0[self.orderAttr] < $1[self.orderAttr] }
                let elements = sortedRows.map{ RowArrayElement(id: $0[self.idAttr], data: $0) }
                self.elements = elements
                self.notifyObservers(arrayChanges: [.Initial(elements)])
            }
            self.notify.valueDidChange()
        })
    }
    
    override func insert(_ row: Row, pos: Pos) {
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
    
    fileprivate func onInsert(_ rows: [Row], elems: inout [Element], changes: inout [Change]) {

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
            changes.append(.Insert(index))
        }
    }

    override func delete(_ id: RelationValue) {
        guard let relation = relation as? TransactionalDatabase.TransactionalRelation else {
            fatalError("delete() is only supported when the underlying relation is mutable")
        }

        // Delete from the relation
        relation.asyncDelete(self.idAttr *== id)
    }

    fileprivate func onDelete(_ ids: [RelationValue], elems: inout [Element], changes: inout [Change]) {
        for id in ids {
            if let index = elems.index(where: { $0.id == id }) {
                elems.remove(at: index)
                changes.append(.Delete(index))
            }
        }
    }

    /// Note: dstIndex is relative to the state of the array *after* the item is removed.
    override func move(srcIndex: Int, dstIndex: Int) {
        // Determine the order of the element in its new position (relative to the current array state)
        let elems = elements ?? []
        let element = elems[srcIndex]
        let elemID = element.id
        
        let (previous, next) = self.adjacentElementsForIndex(dstIndex, notMatching: element, inElements: elems)
        let newOrder = self.orderForElementBetween(previous, next, elems: elems)

        // Update the relation
        relation.asyncUpdate(idAttr *== elemID, newValues: [orderAttr: newOrder])
    }
    
    fileprivate func onUpdate(_ rows: [Row], elems: inout [Element], changes: inout [Change]) {
        for row in rows {
            let newOrder = row[orderAttr]
            if newOrder != .NotFound {
                let id = row[idAttr]
                let element = elementForID(id, elems)!
                changes.append(onMove(element, dstOrder: newOrder, elems: &elems))
            }
        }
    }
    
    // Must be called in the context of the `workOn` scheduler.
    fileprivate func onMove(_ element: Element, dstOrder: RelationValue, elems: inout [Element]) -> Change {
        // Remove the element from the array
        let srcIndex = indexForID(element.id, elems)!
        elems.removeAtIndex(srcIndex)
        
        // Update the order value in the element's row
        element.data[orderAttr] = dstOrder
        
        // Insert the element in its new position
        let dstIndex = elems.insertSorted(element, { $0.data[self.orderAttr] })
        
        return .Move(srcIndex: srcIndex, dstIndex: dstIndex)
    }
    
    fileprivate func adjacentElementsForIndex(_ index: Int, notMatching element: Element, inElements elems: [Element]) -> (Element?, Element?) {
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
    
    fileprivate func orderForElementBetween(_ previous: Element?, _ next: Element?, elems: [Element]) -> RelationValue {
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
        return RelationValue(lo + ((hi - lo) / 2.0))
    }
    
    fileprivate func orderForPos(_ pos: Pos, elems: [Element]) -> RelationValue {
        let prev = pos.previousID.flatMap{ elementForID($0, elems) }
        let next = pos.nextID.flatMap{ elementForID($0, elems) }
        return orderForElementBetween(prev, next, elems: elems)
    }
    
    func relationWillChange(_ relation: Relation) {
        notify.valueWillChange()
    }

    func relationDidChange(_ relation: Relation, result: Result<NegativeSet<Row>, RelationError>) {
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
    public func arrayProperty(_ idAttr: Attribute = "id", orderAttr: Attribute = "order") -> ArrayProperty<RowArrayElement> {
        return RelationArrayProperty(relation: self, idAttr: idAttr, orderAttr: orderAttr)
    }
}
